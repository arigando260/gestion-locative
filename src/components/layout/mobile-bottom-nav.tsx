"use client";

import { Link, usePathname } from "@/i18n/navigation";
import { cn } from "@/lib/utils";
import type { SidebarNavItem } from "@/components/layout/sidebar";

export function MobileBottomNav({ items }: { items: SidebarNavItem[] }) {
  const pathname = usePathname();

  return (
    <nav className="fixed inset-x-0 bottom-0 z-10 flex border-t border-border bg-card md:hidden">
      {items.map((item) => {
        const isActive = pathname === item.href || pathname.startsWith(item.href + "/");
        return (
          <Link
            key={item.href}
            href={item.href}
            className={cn(
              "relative flex flex-1 flex-col items-center gap-1 py-2 text-[11px] font-medium",
              isActive ? "text-primary" : "text-muted-foreground"
            )}
          >
            {item.icon}
            {item.label}
            {item.badgeCount ? (
              <span className="absolute top-1 right-[calc(50%-18px)] size-2 rounded-full bg-status-danger-fg" />
            ) : null}
          </Link>
        );
      })}
    </nav>
  );
}
