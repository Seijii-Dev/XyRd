import {NextRequest} from "next/server";
import {identity} from "@/lib/identity";
import {context,guarded,origin,body,reply,gh,github,ApiError} from "@/lib/api";
import {db,rateLimit} from "@/lib/db";
import {makeState,consumeState,deletionToken} from "@/lib/github-app";
import {validateDeleteTarget,validateDeleteConfirmation} from "@/lib/repository-delete";
export async function POST(req:NextRequest){return guarded(async()=>{
 origin(req);if(req.headers.has("authorization"))throw new ApiError(403,"Repository deletion is only allowed from the owner's browser session");
 const who=await identity(req);if(who.kind!=="user")throw new ApiError(403,"Use the repository owner's GitHub login, not the admin login");
 const data=await body(req);if(data.action!=="prepare"&&data.action!=="delete")throw new ApiError(400,"Invalid action");
 if(!await rateLimit("delete-repo:"+who.subject,8,600))throw new ApiError(429,"Too many requests; wait 10 minutes");
 const c=await context(req,true);const repo=await gh<{id:number;full_name:string;owner:{id:number;type:string}}>(c,"");validateDeleteTarget(c.repo,repo,who.id);
 const kind="delete-repo:"+repo.id+":"+c.repo;
 if(data.action==="prepare")return reply({repo:c.repo,challenge:await makeState(who.subject,kind,300000),expires_in:300});
 validateDeleteConfirmation(c.repo,data);
 const now=Date.now(),expires=now+300000;const lock=await db().prepare("INSERT INTO locks(key,expires) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET expires=excluded.expires WHERE locks.expires<=? RETURNING key").bind("run:"+c.repo,expires,now).first();if(!lock)throw new ApiError(409,"Another session operation exists. Wait and try again.");
 try{
  const checks=await Promise.all(["queued","in_progress","waiting","pending","requested"].map(status=>gh<{total_count:number}>(c,"/actions/runs?status="+status+"&per_page=1")));
  if(checks.some(r=>r.total_count>0))throw new ApiError(409,"Stop all active/queued workflows in the repository before deleting it.");
  const token=await deletionToken(who.subject,c.repo,who.id);
  let deleted=false;
  try{
   const latest=await gh<{id:number;full_name:string;owner:{id:number;type:string}}>(c,"");validateDeleteTarget(c.repo,latest,who.id);if(latest.id!==repo.id)throw new ApiError(409,"Repository changed. Repeat confirmation.");
   await consumeState(String(data.challenge),who.subject,kind);
   await github(token,"/repos/"+c.repo,"DELETE");deleted=true;
  }finally{try{await github(token,"/installation/token","DELETE")}catch{/* token is short-lived and repo-scoped */}}
  if(deleted){
   try{
    await db().prepare("DELETE FROM devices WHERE subject=?").bind(who.subject).run();
    await db().prepare("DELETE FROM credentials WHERE repo=?").bind(c.repo).run();
    await db().prepare("DELETE FROM settings WHERE repo=?").bind(c.repo).run();
    await db().prepare("DELETE FROM repositories WHERE subject=? AND repo=?").bind(who.subject,c.repo).run();
   }catch{return reply({ok:true,deleted:true,cleanup_pending:true,message:"Repository has been deleted on GitHub. Local data cleanup is not finished; contact an administrator."})}
  }
  return reply({ok:true,deleted:true,message:"Repository deleted. This account's XyDesk token and repository data in the dashboard have been cleared. Login remains active."});
 }finally{try{await db().prepare("DELETE FROM locks WHERE key=? AND expires=?").bind("run:"+c.repo,expires).run()}catch{/* lock expires automatically; do not mask a completed deletion */}}
})}