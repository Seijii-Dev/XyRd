import Navigation from "@/app/dashboard/navigation";
import {getServerSession} from "next-auth";
import {authOptions} from "@/lib/auth";
import {redirect} from "next/navigation";
import ConnectionGate from "./connection-gate";
export default async function Layout({children}:{children:React.ReactNode}){let session=null;try{session=await getServerSession(authOptions)}catch{redirect("/login?error=configuration")}if(!session)redirect("/login");return <><Navigation name={session.user?.name}/><main><ConnectionGate>{children}</ConnectionGate></main><footer>Seijixinghe888</footer></>}
