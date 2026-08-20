"use client";

import { useState } from "react";
import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { Link } from "@/i18n/navigation";
import {
  updateLeaseEndDateAction,
  recordKeysReturnedAction,
  closeLeaseDefinitivelyAction,
} from "@/actions/leases";
import { formatDate } from "@/lib/format-date";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import type { DepositBalance } from "@/data/deposits";

// Même map que components/leases/deposit-balance-cards.tsx (dupliquée
// localement : ce fichier est "use client", pas d'import cross-composant
// pour un simple Record).
const DEPOSIT_TYPE_KEY: Record<string, string> = {
  avance_garantie: "typeAvanceGarantie",
  caution_utilities: "typeCautionUtilities",
};

// Mêmes clés que la validation locataire des états des lieux (Module 6) —
// jamais recalculé ici, la vraie source est private.inspection_effective_
// validation_status côté base (property_inspections_effective_status),
// lue via getInspection (data/inspections.ts). Purement informatif : ne
// conditionne jamais l'affichage ni la validité du bouton de clôture.
const VALIDATION_KEY: Record<string, string> = {
  en_attente: "validationEnAttente",
  valide: "validationValide",
  conteste: "validationConteste",
  accepte_tacitement: "validationAccepteTacitement",
};

type Props = {
  leaseId: string;
  // Borne basse pour la restitution des clés — contrôlée uniquement côté
  // action (recordKeysReturnedAction), pas de min sur l'input natif (voir
  // RecordKeysReturnedBanner). Module 10i : date de validation de la
  // résiliation (resilie) ou end_date (actif, Volet B) — NULL si aucune
  // référence connue (dont le cas orphelin, voir data/lease-closure.ts),
  // auquel cas seule la contrainte CHECK leases_keys_returned_after_start
  // protège a minima.
  closureReferenceDate: string | null;
  // "Clôture engagée" (voir data/lease-closure.ts isLeaseClosureEngaged) :
  // calculée côté serveur à partir de données réelles (status='resilie' ou
  // keys_returned_at renseigné) — prime toujours sur closureRevealed
  // ci-dessous, qui ne couvre que l'anticipation côté client avant toute
  // écriture.
  closureEngaged: boolean;
  // Module 10g : un bail sans état des lieux d'entrée finalisé bloquera
  // plus tard toute imputation dégâts (private.validate_deposit_ledger_
  // damage_imputation_requires_inspections, Module 6) — prime sur
  // endDateApproaching (Volet B), jamais revérifié une fois closureEngaged
  // (les bandeaux de clôture sont alors plus actionnables).
  entryInspectionDone: boolean;
  endDateApproaching: boolean;
  endDate: string | null;
  keysReturnedAt: string | null;
  exitInspectionDueDate: string | null;
  exitInspectionDone: boolean;
  exitInspectionValidationStatus: string | null;
  // Bail 'termine' avec au moins un solde de caution non remboursé (voir
  // data/deposits.ts getLeaseDepositBalancesWithRemainder) — tableau vide
  // sinon (y compris pour tout statut autre que 'termine', jamais peuplé
  // par la page appelante dans ce cas). Calculé à la volée : disparaît de
  // lui-même une fois tous les soldes à zéro, aucun statut à gérer.
  depositRefundBalances: DepositBalance[];
};

// Un seul bandeau à la fois (Volet B "fin de bail normale" OU Volet C
// "clôture en cours"), jamais les deux — un seul composant, un seul
// `return`, donc structurellement impossible de les afficher ensemble
// plutôt que garanti par une convention à respecter ailleurs.
//
// "Enclencher la clôture" (Volet B) ne persiste rien : décision actée dès
// la conception du Module 10 (si le staff n'y donne pas suite, rien ne
// change en base, le bandeau réapparaît identique au prochain chargement).
// closureRevealed est donc un état local éphémère, jamais une donnée —
// tant que keys_returned_at n'est pas réellement soumis via le formulaire
// ci-dessous, closureEngaged (donnée serveur) reste faux.
export function LeaseLifecycleBanner({
  leaseId,
  closureReferenceDate,
  closureEngaged,
  entryInspectionDone,
  endDateApproaching,
  endDate,
  keysReturnedAt,
  exitInspectionDueDate,
  exitInspectionDone,
  exitInspectionValidationStatus,
  depositRefundBalances,
}: Props) {
  const [closureRevealed, setClosureRevealed] = useState(false);

  // En tête : le seul cas pertinent pour un bail 'termine', statut que le
  // reste de ce composant ne considère jamais (closureStatus, source des
  // autres props, est toujours null pour 'termine' — voir data/lease-
  // closure.ts et la page appelante).
  if (depositRefundBalances.length > 0) {
    return <DepositRefundPendingBanner leaseId={leaseId} balances={depositRefundBalances} />;
  }

  if (closureEngaged) {
    if (exitInspectionDone) {
      return (
        <ReadyToCloseBanner
          leaseId={leaseId}
          validationStatus={exitInspectionValidationStatus}
        />
      );
    }
    if (keysReturnedAt === null) {
      return (
        <RecordKeysReturnedBanner leaseId={leaseId} closureReferenceDate={closureReferenceDate} />
      );
    }
    return (
      <ExitInspectionDueBanner leaseId={leaseId} dueDate={exitInspectionDueDate} />
    );
  }

  if (!entryInspectionDone) {
    return <EntryInspectionDueBanner leaseId={leaseId} />;
  }

  if (endDateApproaching) {
    if (closureRevealed) {
      return (
        <RecordKeysReturnedBanner leaseId={leaseId} closureReferenceDate={closureReferenceDate} />
      );
    }
    return (
      <LeaseEndingBanner
        leaseId={leaseId}
        endDate={endDate}
        onStartClosure={() => setClosureRevealed(true)}
      />
    );
  }

  return null;
}

// ----------------------------------------------------------------------------
// Volet B — fin de bail normale.
// ----------------------------------------------------------------------------

function LeaseEndingBanner({
  leaseId,
  endDate,
  onStartClosure,
}: {
  leaseId: string;
  endDate: string | null;
  onStartClosure: () => void;
}) {
  const t = useTranslations("leases");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(updateLeaseEndDateAction, null);

  return (
    <Card className="max-w-md border-amber-500/50">
      <CardHeader>
        <CardTitle className="text-base">
          {endDate ? t("leaseEndingBanner", { date: formatDate(endDate, locale) }) : t("leaseEndingBannerNoDate")}
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <form action={formAction} className="flex flex-col gap-2">
          <input type="hidden" name="lease_id" value={leaseId} />
          <Label htmlFor="renew_end_date">{t("endDate")}</Label>
          <div className="flex items-center gap-2">
            <Input
              id="renew_end_date"
              name="end_date"
              type="date"
              defaultValue={endDate ?? ""}
              className="w-fit"
            />
            <SubmitButton pendingText={tc("loading")} variant="outline">
              {t("renewLease")}
            </SubmitButton>
          </div>
          <FormMessage state={state} />
        </form>

        <Button type="button" variant="outline" className="w-fit" onClick={onStartClosure}>
          {t("startClosure")}
        </Button>
      </CardContent>
    </Card>
  );
}

// ----------------------------------------------------------------------------
// Module 10g — état des lieux d'entrée manquant, tant que le bail n'est
// pas engagé en clôture. Pas de fenêtre de délai (contrairement à
// ExitInspectionDueBanner) : leases_closure_status ne calcule aucun seuil
// côté entrée, seulement l'existence d'un document finalisé.
// ----------------------------------------------------------------------------

function EntryInspectionDueBanner({ leaseId }: { leaseId: string }) {
  const t = useTranslations("leases");

  return (
    <Card className="max-w-md border-amber-500/50">
      <CardHeader>
        <CardTitle className="text-base">{t("entryInspectionDueBanner")}</CardTitle>
      </CardHeader>
      <CardContent>
        <Button
          className="w-fit"
          render={<Link href={`/leases/${leaseId}/inspections/new?type=entree`} />}
          nativeButton={false}
        >
          {t("createEntryInspection")}
        </Button>
      </CardContent>
    </Card>
  );
}

// ----------------------------------------------------------------------------
// Volet C — restitution des clés → état des lieux de sortie → clôture.
// ----------------------------------------------------------------------------

function RecordKeysReturnedBanner({
  leaseId,
  closureReferenceDate,
}: {
  leaseId: string;
  closureReferenceDate: string | null;
}) {
  const t = useTranslations("leases");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(recordKeysReturnedAction, null);
  const today = new Date().toISOString().slice(0, 10);
  const [dateValue, setDateValue] = useState(today);

  // Avertissement non bloquant, purement informatif : si la date choisie
  // est déjà à plus de 7 jours dans le passé, la fenêtre de l'état des
  // lieux de sortie (keys_returned_at + 7, voir exit_inspection_due_date)
  // sera déjà expirée au moment de l'enregistrement — reste une saisie
  // légitime (retard administratif), donc aucun blocage serveur associé.
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
  const showOldDateWarning = dateValue < sevenDaysAgo.toISOString().slice(0, 10);

  return (
    <Card className="max-w-md border-amber-500/50">
      <CardHeader>
        <CardTitle className="text-base">{t("keysReturnedBanner")}</CardTitle>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="flex flex-col gap-2">
          <input type="hidden" name="lease_id" value={leaseId} />
          {closureReferenceDate && (
            <input type="hidden" name="closure_reference_date" value={closureReferenceDate} />
          )}
          <Label htmlFor="keys_returned_at">{t("keysReturnedAtLabel")}</Label>
          <div className="flex items-center gap-2">
            <Input
              id="keys_returned_at"
              name="keys_returned_at"
              type="date"
              value={dateValue}
              onChange={(e) => setDateValue(e.target.value)}
              max={today}
              className="w-fit"
              required
            />
            <SubmitButton pendingText={tc("loading")}>{t("recordKeysReturned")}</SubmitButton>
          </div>
          {showOldDateWarning && (
            <p className="text-sm text-amber-600">{t("keysReturnedOldDateWarning")}</p>
          )}
          <FormMessage state={state} />
        </form>
      </CardContent>
    </Card>
  );
}

function ExitInspectionDueBanner({
  leaseId,
  dueDate,
}: {
  leaseId: string;
  dueDate: string | null;
}) {
  const t = useTranslations("leases");
  const locale = useLocale();

  return (
    <Card className="max-w-md border-amber-500/50">
      <CardHeader>
        <CardTitle className="text-base">
          {dueDate ? t("exitInspectionDueBanner", { date: formatDate(dueDate, locale) }) : t("exitInspectionDueBannerNoDate")}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <Button
          className="w-fit"
          render={<Link href={`/leases/${leaseId}/inspections/new?type=sortie`} />}
          nativeButton={false}
        >
          {t("createExitInspection")}
        </Button>
      </CardContent>
    </Card>
  );
}

function ReadyToCloseBanner({
  leaseId,
  validationStatus,
}: {
  leaseId: string;
  validationStatus: string | null;
}) {
  const t = useTranslations("leases");
  const ti = useTranslations("inspections");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(closeLeaseDefinitivelyAction, null);

  return (
    <Card className="max-w-md border-amber-500/50">
      <CardHeader>
        <CardTitle className="text-base">{t("readyToCloseBanner")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {validationStatus && (
          <p className="text-sm text-muted-foreground">
            {ti("validationStatus")}: {ti(VALIDATION_KEY[validationStatus] ?? "validationEnAttente")}
          </p>
        )}
        <form action={formAction} className="flex flex-col gap-2">
          <input type="hidden" name="lease_id" value={leaseId} />
          <SubmitButton pendingText={tc("loading")}>{t("closeLeaseButton")}</SubmitButton>
          <FormMessage state={state} />
        </form>
      </CardContent>
    </Card>
  );
}

// ----------------------------------------------------------------------------
// Bail 'termine' — solde(s) de caution restant à rembourser.
// ----------------------------------------------------------------------------

function DepositRefundPendingBanner({
  leaseId,
  balances,
}: {
  leaseId: string;
  balances: DepositBalance[];
}) {
  const t = useTranslations("leases");
  const td = useTranslations("deposits");

  return (
    <Card className="max-w-md border-amber-500/50">
      <CardHeader>
        <CardTitle className="text-base">{t("depositRefundPendingBanner")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <ul className="flex flex-col gap-1 text-sm text-muted-foreground">
          {balances.map((balance) => (
            <li key={balance.deposit_type}>
              {td(DEPOSIT_TYPE_KEY[balance.deposit_type ?? ""] ?? "typeAvanceGarantie")}: {balance.balance}
            </li>
          ))}
        </ul>
        <Button
          className="w-fit"
          render={<Link href={`/leases/${leaseId}/deposits`} />}
          nativeButton={false}
        >
          {t("depositRefundPendingLink")}
        </Button>
      </CardContent>
    </Card>
  );
}
