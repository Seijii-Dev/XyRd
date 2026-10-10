"use client";
import {signIn} from "next-auth/react";
export default function Button(){return <button onClick={()=>signIn("github",{callbackUrl:"/dashboard"})}>Login GitHub · identitas saja →</button>}
