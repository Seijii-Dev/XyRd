import {NextRequest} from "next/server";
import {context,guarded,reply,origin,gh,ApiError} from "@/lib/api";
import {db,rateLimit} from "@/lib/db";
import {openPassword} from "@/lib/vault";
export async function POST(req:NextRequest){return guarded(async()=>{const c=await context(req,true);origin(req);if(!await rateLimit("reveal:"+c.subject,20,300))throw new ApiError(429,"Too many requests to reveal the password");
 const repo=await gh<{permissions?:{push?:boolean}}>(c,"");if(!c.installationId&&!repo.permissions?.push)throw new ApiError(403,"Repository access is not allowed");
 const row=await db().prepare("SELECT payload,remote_updated FROM credentials WHERE repo=?").bind(c.repo).first<{payload:string;remote_updated:string}>();
 if(!row)throw new ApiError(404,"No copy of the password in the dashboard. GitHub cannot re-display old secrets. Enter a new password via Setup.");
 const remote=await gh<{updated_at:string}>(c,"/actions/secrets/RDP_PASSWORD");if(remote.updated_at!==row.remote_updated)throw new ApiError(409,"The password on GitHub has changed. Update via Setup so the dashboard copy is synchronized.");return reply({password:openPassword(c.repo,row.payload)});
})}
export async function DELETE(req:NextRequest){return guarded(async()=>{const c=await context(req,true);origin(req);await db().prepare("DELETE FROM credentials WHERE repo=?").bind(c.repo).run();return reply({ok:true})})}