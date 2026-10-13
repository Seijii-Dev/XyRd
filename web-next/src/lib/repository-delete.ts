import {ApiError} from "./api";
export function validateDeleteTarget(repo:string,data:{id:number;full_name:string;owner:{id:number;type:string}},accountId:string){
 if(!Number.isSafeInteger(data.id)||data.id<=0||data.full_name!==repo||String(data.owner.id)!==accountId||data.owner.type!=="User")throw new ApiError(403,"Only an active repository belonging to your own account can be deleted");
 if(["seijii-dev/xyrd","xykal/xyrdp","xykal/xydesk-remote"].includes(repo.toLowerCase()))throw new ApiError(403,"Service source repositories are protected from deletion via the dashboard");
}
export function validateDeleteConfirmation(repo:string,data:Record<string,unknown>){
 if(data.confirmation!==repo||data.acknowledge!==true||typeof data.challenge!=="string")throw new ApiError(400,"Type the full repository name and acknowledge the deletion impact");
}