import {ApiError,Context,gh} from "./api";
import {db} from "./db";
export const choices:Record<string,string[]>={durasi_menit:["15","30","60","120","180","240","300","330","360"],akses:["tailscale"],runner:["github","self-hosted"],microphone:["yes","no"],debloat:["light","full","no"],win11:["yes","no"],xydesk:["yes","no"],ekstra:["yes","no"]};
export const defaults:Record<string,string>={durasi_menit:"360",hostname:"rdpfree",rdp_user:"xyadmin",akses:"tailscale",runner:"github",microphone:"yes",debloat:"light",win11:"yes",xydesk:"yes",ekstra:"yes"};
export function validate(raw:Record<string,unknown>){const inputs={...defaults};for(const [k,v] of Object.entries(raw)){if(k==="wallpaper"||k==="wallpaper_url")continue;if(!(k in defaults)||typeof v!=="string")throw new ApiError(400,"Unknown parameter: "+k);inputs[k]=v;}
 for(const [k,allowed] of Object.entries(choices))if(!allowed.includes(inputs[k]))throw new ApiError(400,"Invalid choice: "+k);
 if(!/^[a-zA-Z0-9][a-zA-Z0-9-]{0,29}$/.test(inputs.hostname))throw new ApiError(400,"Hostname must be 1–30 letters, numbers, or hyphens");
 if(!/^[a-zA-Z][a-zA-Z0-9_-]{2,19}$/.test(inputs.rdp_user)||/^(administrator|guest|defaultaccount|wdagutilityaccount|system|localservice|networkservice|con|prn|aux|nul)$/i.test(inputs.rdp_user))throw new ApiError(400,"Invalid RDP username");
return inputs;}
export function migrateSettings(raw:Record<string,unknown>){
 const migrated={...raw};for(const k of Object.keys(migrated)){if(migrated[k] === "ya") migrated[k]="yes";if(migrated[k] === "tidak") migrated[k]="no";if(migrated[k] === "ringan") migrated[k]="light";}delete migrated.tunnel_provider;delete migrated.wallpaper;delete migrated.wallpaper_url;migrated.akses="tailscale";
 if(!("runner" in migrated)){migrated.runner="github";}
 return validate(migrated);
}
export async function loadSettings(repo:string){const r=await db().prepare("SELECT inputs FROM settings WHERE repo=?").bind(repo).first<{inputs:string}>();return r?migrateSettings(JSON.parse(r.inputs)):{...defaults};}
export type Run={id:number;status:string;conclusion:string|null;created_at:string;run_started_at:string;html_url:string;name:string;workflow_id:number};
export async function runs(ctx:Context){return (await gh<{workflow_runs:Run[]}>(ctx,"/actions/workflows/rdp-6h.yml/runs?per_page=30")).workflow_runs;}
export const active=(r:Run)=>["queued","in_progress","waiting","requested","pending"].includes(r.status);