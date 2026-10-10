import {NextRequest} from "next/server";
import {context,guarded,reply,origin,body,gh,ApiError} from "@/lib/api";
import {inspect} from "@/lib/setup";
import {runs,active,validate,loadSettings} from "@/lib/workflow";
import {db,rateLimit} from "@/lib/db";
export async function GET(req:NextRequest){return guarded(async()=>{const c=await context(req);return reply({repo:c.repo,runs:await runs(c)})})}
export async function POST(req:NextRequest){return guarded(async()=>{const c=await context(req);if(c.kind!=="device")origin(req);
 const data=await body(req);if(data.confirm!==true)throw new ApiError(400,"Confirmation to start the workflow is required");
 if(!await rateLimit("dispatch:"+c.repo,2,300))throw new ApiError(429,"Maximum 2 run attempts per 5 minutes");
 const now=Date.now();const lock=await db().prepare("INSERT INTO locks(key,expires) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET expires=excluded.expires WHERE locks.expires<=? RETURNING key").bind("run:"+c.repo,now+90000,now).first();if(!lock)throw new ApiError(409,"Another run request is being processed");
 // Lock expires after 90 seconds even if the dispatch response is lost, to prevent double starts.
 if((await runs(c)).some(active))throw new ApiError(409,"There is still an active or queued run");
 const setup=await inspect(c);if(!setup.ready)throw new ApiError(400,"Complete repository Setup, Actions, and secrets first");
 const inputs=await loadSettings(c.repo);const valid=validate(inputs);
 const repo=await gh<{default_branch:string;permissions?:{push?:boolean}}>(c,"");if(!c.installationId&&!repo.permissions?.push)throw new ApiError(403,"Write access to the repository is required");
 if(valid.runner!=="self-hosted"&&["samp","roblox","minecraft_java","minecraft_bedrock"].some(k=>valid[k]==="ya"))throw new ApiError(400,"Game preparation requires a dedicated Windows self-hosted runner you own. Change Settings or disable the game.");
 const workflow=await gh<{content:string}>(c,"/contents/.github/workflows/rdp-6h.yml?ref="+encodeURIComponent(repo.default_branch));
 if(!Buffer.from(workflow.content,"base64").toString("utf8").includes("# rdpfree-workflow-schema: 3"))throw new ApiError(409,"Repository is still using an old workflow. Sync workflow, scripts, and assets from xykal/XyRDP before starting; the App does not have permission to write source.");
 const secrets=await gh<{secrets:{name:string}[]}>(c,"/actions/secrets?per_page=100");const names=secrets.secrets.map(s=>s.name);const required=["RDP_PASSWORD","TAILSCALE_AUTH_KEY"];const missing=required.filter(k=>!names.includes(k));if(missing.length)throw new ApiError(400,"Secrets are incomplete: "+missing.join(", "));
 await gh(c,"/actions/workflows/rdp-6h.yml/dispatches","POST",{ref:repo.default_branch,inputs:valid});return reply({ok:true,repo:c.repo,inputs:valid,message:"Workflow accepted by GitHub. Status will appear after queuing."},202);
 })}