"use client";

import { useActionState, useState } from "react";
import { useTranslations, useLocale } from "next-intl";
import {
  assignAgentToPropertyAction,
  unassignAgentFromPropertyAction,
} from "@/actions/property-agent-assignments";
import { Button } from "@/components/ui/button";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { formatDateTime } from "@/lib/format-date";
import type {
  PropertyAgentAssignment,
  AvailableAgent,
} from "@/data/property-agent-assignments";

// Visible seulement pour un admin (gating côté page, via
// can(permissions, 'property_agent_assignments', 'create'/'delete') --
// même mécanisme que l'écran Équipe, pas de nouvelle infrastructure).
export function PropertyAgentAssignments({
  propertyId,
  assignments,
  availableAgents,
}: {
  propertyId: string;
  assignments: PropertyAgentAssignment[];
  availableAgents: AvailableAgent[];
}) {
  const t = useTranslations("properties");
  const locale = useLocale();
  const [state, formAction] = useActionState(assignAgentToPropertyAction, null);
  const [removingId, setRemovingId] = useState<string | null>(null);
  const [removeError, setRemoveError] = useState<string | null>(null);

  async function handleRemove(assignmentId: string) {
    setRemoveError(null);
    setRemovingId(assignmentId);
    const result = await unassignAgentFromPropertyAction(assignmentId, propertyId);
    setRemovingId(null);
    if (!result?.success) {
      setRemoveError(result?.message ?? t("agentAssignmentRemoveError"));
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <h2 className="text-lg font-semibold">{t("agentAssignmentsTitle")}</h2>

      {assignments.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("agentAssignmentsEmpty")}</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {assignments.map((assignment) => (
            <li
              key={assignment.id}
              className="flex items-center justify-between gap-3 border-b border-border pb-2 text-sm last:border-0 last:pb-0"
            >
              <span>
                {assignment.full_name || assignment.email}
                <span className="ml-2 text-xs text-muted-foreground">
                  {t("agentAssignedOn", { date: formatDateTime(assignment.assigned_at, locale) })}
                </span>
              </span>
              <Button
                type="button"
                variant="outline"
                size="sm"
                disabled={removingId === assignment.id}
                onClick={() => handleRemove(assignment.id)}
              >
                {removingId === assignment.id ? t("agentAssignmentRemoving") : t("agentAssignmentRemove")}
              </Button>
            </li>
          ))}
        </ul>
      )}

      {removeError ? (
        <p className="text-sm text-destructive" role="alert">
          {removeError}
        </p>
      ) : null}

      {availableAgents.length > 0 ? (
        <form action={formAction} className="flex flex-col gap-3 border-t border-border pt-3">
          <input type="hidden" name="property_id" value={propertyId} />
          <SelectField
            name="agent_id"
            label={t("agentAssignmentSelectLabel")}
            defaultValue={availableAgents[0]?.id}
            options={availableAgents.map((agent) => ({
              value: agent.id,
              label: agent.full_name || agent.email,
            }))}
          />
          {state && !state.success ? (
            <p className="text-sm text-destructive" role="alert">
              {state.message}
            </p>
          ) : null}
          <SubmitButton pendingText={t("agentAssignmentSubmitting")} className="w-fit">
            {t("agentAssignmentSubmit")}
          </SubmitButton>
        </form>
      ) : (
        <p className="text-sm text-muted-foreground">{t("agentAssignmentsNoneAvailable")}</p>
      )}
    </div>
  );
}
