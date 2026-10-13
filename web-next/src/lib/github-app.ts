import {createSign,randomBytes} from "node:crypto";
import {db} from "./db";
import {github,ApiError,hash} from "./api";
import {sealPassword,openPassword} from "./vault";
export const SITE=process.env.NEXTAUTH_URL||"https://seiji-rmd-web.vercel.app";
export const APP_PERMISSIONS={contents:"read",actions:"write",secrets:"write",metadata:"read"};
export const DELETE_PERMISSIONS={administration:"write",metadata:"read"};
export type AppConfig={id:number;slug:string;pem:string};
export type Installation={subject:string;installation_id:number;account_id:string;login:string};
export async function appConfig(){const row=await db().prepare("SELECT payload FROM app_config WHERE name='github'").first<{payload:string}>();return row?JSON.parse(openPassword("system:github-app",row.payload)) as AppConfig:null;}
export async function saveApp(config:AppConfig){if(await appConfig())throw new ApiError(409,"GitHub App is already configured");await db().prepare("INSERT INTO app_config(name,payload) VALUES('github',?)").bind(sealPassword("system:github-app",JSON.stringify(config))).run();}
export function appJWT(config:AppConfig){const now=Math.floor(Date.now()/1000);const encode=(x:unknown)=>Buffer.from(JSON.stringify(x)).toString("base64url");const value=encode({alg:"RS256",typ:"JWT"})+"."+encode({iat:now-30,exp:now+540,iss:String(config.id)});return value+"."+createSign("RSA-SHA256").update(value).sign(config.pem).toString("base64url");}
export async function installation(subject:string){return db().prepare("SELECT subject,installation_id,account_id,login FROM app_installations WHERE subject=?").bind(subject).first<Installation>();}
export async function verifyInstallation(id:number,accountId:string){const config=await appConfig();if(!config)throw new ApiError(503,"GitHub App has not been registered by an admin");const data=await github<{id:number;app_id:number;account:{id:number;login:string;type:string};suspended_at:string|null}>(appJWT(config),"/app/installations/"+id);
 if(data.app_id!==config.id||data.account.type!=="User"||String(data.account.id)!==accountId||data.suspended_at)throw new ApiError(403,"Installation must be active and belong to the personal account currently logged in");return data;}
export async function installationToken(subject:string,repo?:string){const config=await appConfig();if(!config)throw new ApiError(409,"Login successful. Admin has not enabled the GitHub App for repository access.");const link=await installation(subject);if(!link)throw new ApiError(409,"Login successful. Connect repositories by installing the GitHub App first.");
 if(repo&&repo.split("/")[0].toLowerCase()!==link.login.toLowerCase())throw new ApiError(403,"Repository does not belong to this installation account");
 // Mint a short-lived installation token for this exact repository. GitHub enforces removals/revocation.
 const d=await github<{token:string}>(appJWT(config),"/app/installations/"+link.installation_id+"/access_tokens","POST",{permissions:APP_PERMISSIONS,...(repo?{repositories:[repo.split("/")[1]]}:{})});return {token:d.token,installationId:link.installation_id};
}
export async function makeState(subject:string,kind:string,ttlMs=3600000){const value=randomBytes(32).toString("base64url");await db().prepare("INSERT INTO app_states(hash,subject,kind,expires) VALUES(?,?,?,?)").bind(hash(value),subject,kind,Date.now()+ttlMs).run();return value;}
export async function consumeState(value:string,subject:string,kind:string){if(!/^[A-Za-z0-9_-]{43}$/.test(value))throw new ApiError(403,"Invalid state");const result=await db().prepare("DELETE FROM app_states WHERE hash=? AND subject=? AND kind=? AND expires>? RETURNING hash").bind(hash(value),subject,kind,Date.now()).first();if(!result)throw new ApiError(403,"Request already used or expired. Start again from the dashboard.");}
export function manifest(){return {name:"Seiji-RMD Repository",url:SITE,description:"Access selected repos to read workflows, start/stop Actions, store Actions Secrets, and delete repos after owner confirmation. Separate identity login.",public:true,redirect_url:SITE+"/api/admin/github-app/callback",setup_url:SITE+"/api/github-app/callback",setup_on_update:true,request_oauth_on_install:false,hook_attributes:{url:SITE+"/api/github-app/webhook",active:false},default_events:[],default_permissions:{...APP_PERMISSIONS,...DELETE_PERMISSIONS}};}

// Destructive capability is never included in ordinary browser/device tokens.
export async function deletionToken(subject:string,repo:string,accountId:string){
 const link=await installation(subject);if(!link||link.account_id!==accountId||repo.split("/")[0].toLowerCase()!==link.login.toLowerCase())throw new ApiError(403,"Repository does not belong to this account");
 const config=await appConfig();if(!config)throw new ApiError(409,"GitHub App is not active");
 const state=await github<{account:{id:number;type:string};suspended_at:string|null;permissions:{administration?:string}}>(appJWT(config),"/app/installations/"+link.installation_id);
 if(String(state.account.id)!==accountId||state.account.type!=="User"||state.suspended_at)throw new ApiError(403,"Installation is not active or does not belong to you");
 if(state.permissions.administration!=="write")throw new ApiError(403,"Delete permission is not enabled. Admin needs to add Administration: Read and write to the GitHub App, then the repo owner must approve the permission update on GitHub. Repo not deleted.");
 const result=await github<{token:string}>(appJWT(config),"/app/installations/"+link.installation_id+"/access_tokens","POST",{repositories:[repo.split("/")[1]],permissions:DELETE_PERMISSIONS});return result.token;
}