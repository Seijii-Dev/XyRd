import {NextRequest} from "next/server";
import {identity} from "@/lib/identity";
import {guarded,reply,origin,ApiError} from "@/lib/api";
import {db} from "@/lib/db";
export async function POST(req:NextRequest){return guarded(async()=>{origin(req);const who=await identity(req);if(who.kind!=="user")throw new ApiError(403,"GitHub App users only");await db().prepare("DELETE FROM app_installations WHERE subject=?").bind(who.subject).run();await db().prepare("DELETE FROM devices WHERE subject=?").bind(who.subject).run();return reply({ok:true,message:"Dashboard connection and device tokens have been revoked. Uninstall the app on GitHub to remove the installation as well."})})}