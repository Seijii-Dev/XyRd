import {getServerSession} from "next-auth";
import {authOptions} from "@/lib/auth";
import {redirect} from "next/navigation";
import Button from "./button";
export default async function Login({searchParams}:{searchParams:Promise<{error?:string}>}){
 let session=null;let configurationError=false;
 try{session=await getServerSession(authOptions)}catch{configurationError=true}
 if(session) redirect("/dashboard");
 const {error}=await searchParams;
 return <main className="login"><span className="eyebrow">Seiji-RMD / Account</span><h1>Welcome back.</h1><p>Login is only for identity. Repository access must be requested separately after you sign in.</p><section className="card"><h2>One account. One control room.</h2><p>Step 1: sign in with your GitHub profile. Step 2: Install the GitHub App and select the repositories you allow.</p>{error&&<p className="error">Sign-in did not complete successfully. Try again or check your OAuth configuration.</p>}{configurationError&&<p className="error">The dashboard is missing its production authentication secret. Add <code>NEXTAUTH_SECRET</code> in the deployment environment, then redeploy.</p>}<Button/></section><footer>Seijixinghe888</footer></main>
}