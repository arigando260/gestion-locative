import { createNavigation } from "next-intl/navigation";
import { routing } from "./routing";

// Link, redirect, usePathname, useRouter conscients de la locale — à utiliser
// partout à la place des équivalents next/navigation directs.
export const { Link, redirect, usePathname, useRouter, getPathname } =
  createNavigation(routing);
