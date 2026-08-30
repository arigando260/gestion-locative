"use client";

import type { ReactNode } from "react";
import { Link, usePathname } from "@/i18n/navigation";
import { AvatarInitials } from "@/components/ui/avatar-initials";
import { cn } from "@/lib/utils";

export type SidebarNavItem = {
  href: string;
  label: string;
  // Élément déjà rendu (ex. <LayoutGrid className="size-[17px]" />), pas un
  // type de composant : une référence de fonction ne peut pas traverser la
  // frontière server→client (Sidebar est "use client"), un élément React
  // (objet sérialisable) le peut.
  icon: ReactNode;
  badgeCount?: number;
};

export type SidebarSection = {
  label: string;
  items: SidebarNavItem[];
};

export function Sidebar({
  appName,
  appSubtitle,
  sections,
  footerName,
  footerSubtitle,
  extra,
}: {
  appName: string;
  appSubtitle: string;
  sections: SidebarSection[];
  footerName: string;
  footerSubtitle: string;
  extra?: React.ReactNode;
}) {
  const pathname = usePathname();

  return (
    <aside className="sticky top-0 flex h-screen w-[252px] shrink-0 flex-col overflow-auto border-r border-border bg-card">
      <div className="flex items-center gap-[11px] px-5 pt-[22px] pb-5">
        <div className="flex size-[34px] items-center justify-center rounded-[9px] bg-primary text-[17px] font-bold text-primary-foreground">
          {appName.charAt(0)}
        </div>
        <div>
          <div className="text-[16px] font-bold tracking-tight">{appName}</div>
          <div className="mt-px text-[11px] text-muted-foreground">{appSubtitle}</div>
        </div>
      </div>

      {extra}

      {sections.map((section, index) => (
        <div key={section.label || index}>
          {section.label ? (
            <div className="px-6 pt-2 pb-2 text-[10.5px] font-semibold tracking-[0.09em] text-muted-foreground/80">
              {section.label}
            </div>
          ) : null}
          <nav className="flex flex-col gap-0.5 px-3 pt-2 pb-2">
            {section.items.map((item) => {
              const isActive =
                pathname === item.href || pathname.startsWith(item.href + "/");
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "flex items-center gap-[11px] rounded-lg px-3 py-[9px] text-[13.5px] hover:bg-muted",
                    isActive
                      ? "bg-accent font-semibold text-accent-foreground"
                      : "font-medium text-[#52525b]"
                  )}
                >
                  {item.icon}
                  <span className="flex-1">{item.label}</span>
                  {item.badgeCount ? (
                    <span className="inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-full bg-status-warning-bg px-1 text-[10.5px] font-bold text-status-warning-fg">
                      {item.badgeCount}
                    </span>
                  ) : null}
                </Link>
              );
            })}
          </nav>
        </div>
      ))}

      <div className="mt-auto flex items-center gap-[10px] border-t border-border px-5 py-4">
        <AvatarInitials name={footerName} tone="person" />
        <div className="min-w-0">
          <div className="truncate text-[13px] font-semibold">{footerName}</div>
          <div className="truncate text-[11px] text-muted-foreground">{footerSubtitle}</div>
        </div>
      </div>
    </aside>
  );
}
