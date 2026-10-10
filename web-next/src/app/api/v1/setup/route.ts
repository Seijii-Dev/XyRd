import {NextRequest} from "next/server";
import {context,guarded,reply,origin,body,github,gh,ApiError} from "@/lib/api";
import {db,rateLimit} from "@/lib/db";
import {TEMPLATE,inspect,finishSetup} from "@/lib/setup";
import {defaults} from "@/lib/workflow";
export async function GET(req:NextRequest){return guarded(async()=>reply(await inspect(await context(req))))}
export async function POST(req:NextRequest){return guarded(async()=>{
 const c=await context(req,true);origin(req);const data=await body(req);
 if(data.action==="finish"){try{await finishSetup(c)}catch(e){if(e instanceof ApiError&&[404,409].includes(e.status))throw new ApiError(409,"GitHub is still setting up the repository or the workflow is not yet available. Wait a few seconds, then click Continue setup again.");throw e}return reply(await inspect(c));}
 if(c.installationId)throw new ApiError(400,"Create the repo from the template on GitHub, then select the repo through the Connect repository page.");
 if(!["create","connect"].includes(String(data.action)))throw new ApiError(400,"Unknown action");
 const name=typeof data.name==="string"?data.name.trim():"";
 if(!/^[A-Za-z0-9][A-Za-z0-9._-]{0,89}$/.test(name))throw new ApiError(400,"Repository name must be 1–90 letters, numbers, dots, dashes, or underscores");
 const who=await github<{login:string}>(c.token,"/user");const repo=who.login+"/"+name;
 if(data.action==="create"){
  if(data.confirm!==true)throw new ApiError(400,"Confirmation for repository creation is required");
  if(!await rateLimit("create-repo:"+c.subject,3,3600))throw new ApiError(429,"Maximum 3 repository creation attempts per hour");
  const r=await github<{full_name:string}>(c.token,"/repos/"+TEMPLATE+"/generate","POST",{owner:who.login,name,private:data.private===true,include_all_branches:false,description:"RdpFree Windows workflow — credit KallAncrit"});
  if(r.full_name.toLowerCase()!==repo.toLowerCase())throw new ApiError(502,"The repository generated from the template does not match");
  await db().prepare("INSERT INTO repositories(subject,repo,state,updated) VALUES(?,?,'initializing',?) ON CONFLICT(subject) DO UPDATE SET repo=excluded.repo,state=excluded.state,updated=excluded.updated").bind(c.subject,r.full_name,Date.now()).run();
  await db().prepare("INSERT INTO settings(repo,inputs,updated) VALUES(?,?,?) ON CONFLICT(repo) DO NOTHING").bind(r.full_name,JSON.stringify({...defaults,akses:"tailscale"}),Date.now()).run();
  // Return immediately. GitHub may need time before refs and workflows become visible.
  return reply({repo:r.full_name,created:true,importing:true},201);
 }
 const chosen={...c,repo};const r=await gh<{permissions?:{push:boolean}}>(chosen,"");if(!r.permissions?.push)throw new ApiError(403,"The repository must belong to your account and be writable");
 await gh(chosen,"/contents/.github/workflows/rdp-6h.yml");
 await db().prepare("INSERT INTO repositories(subject,repo,state,updated) VALUES(?,?,'ready',?) ON CONFLICT(subject) DO UPDATE SET repo=excluded.repo,state=excluded.state,updated=excluded.updated").bind(c.subject,repo,Date.now()).run();
 return reply(await inspect(chosen));
})}