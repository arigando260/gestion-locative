// Template FIXE (V1), même principe que invoice-document.tsx/receipt-document.tsx
// — rendu UNIQUEMENT côté serveur (renderToBuffer, voir actions/lease-contracts.tsx).
import { Document, Page, View, Text } from "@react-pdf/renderer";
import { documentStyles, DocumentHeader, type OrganizationHeaderInfo } from "./document-header";

export type LeaseContractDocumentData = {
  organization: OrganizationHeaderInfo;
  tenantName: string;
  propertyLabel: string;
  propertyAddress: string;
  contractReference: string;
  issuedDate: string;
  startDate: string;
  endDate: string | null;
  rentAmount: string;
  paymentFrequencyLabel: string;
  securityDepositAmount: string;
  utilityDepositAmount: string | null;
  // Déjà résolu (bail > organisation > rien) côté data/lease-contracts.ts —
  // ce composant ne fait qu'afficher, jamais de logique de repli ici.
  specialTerms: string | null;
};

// Contenu minimal demandé (Module 10, Volet A) : coordonnées organisation
// (DocumentHeader, partagé), locataire, bien, montants convenus à la
// création du bail (jamais recalculés ici — ce sont les colonnes leases.*
// fixées à l'origine, voir data/lease-contracts.ts), dates. Pas d'éditeur :
// le contenu vient entièrement de ce que le bail portait déjà.
export function LeaseContractDocument({ data }: { data: LeaseContractDocumentData }) {
  return (
    <Document>
      <Page size="A4" style={documentStyles.page}>
        <DocumentHeader
          organization={data.organization}
          documentTitle="CONTRAT DE BAIL"
          reference={data.contractReference}
          date={data.issuedDate}
        />
        <View style={documentStyles.divider} />

        <View style={documentStyles.section}>
          <Text style={documentStyles.sectionLabel}>Locataire</Text>
          <Text style={documentStyles.sectionValue}>{data.tenantName}</Text>
        </View>

        <View style={documentStyles.section}>
          <Text style={documentStyles.sectionLabel}>Logement</Text>
          <Text style={documentStyles.sectionValue}>{data.propertyLabel}</Text>
          <Text style={documentStyles.sectionValue}>{data.propertyAddress}</Text>
        </View>

        <View style={documentStyles.section}>
          <Text style={documentStyles.sectionLabel}>Durée du bail</Text>
          <Text style={documentStyles.sectionValue}>
            {data.startDate} → {data.endDate ?? "durée indéterminée"}
          </Text>
        </View>

        <View style={documentStyles.section}>
          <Text style={documentStyles.sectionLabel}>Loyer ({data.paymentFrequencyLabel})</Text>
          <Text style={documentStyles.sectionValue}>{data.rentAmount}</Text>
        </View>

        <View style={documentStyles.section}>
          <Text style={documentStyles.sectionLabel}>Avance de garantie</Text>
          <Text style={documentStyles.sectionValue}>{data.securityDepositAmount}</Text>
        </View>

        {data.utilityDepositAmount !== null && (
          <View style={documentStyles.section}>
            <Text style={documentStyles.sectionLabel}>Caution eau/électricité</Text>
            <Text style={documentStyles.sectionValue}>{data.utilityDepositAmount}</Text>
          </View>
        )}

        {data.specialTerms !== null && (
          <View style={documentStyles.section}>
            <Text style={documentStyles.sectionLabel}>Clauses particulières</Text>
            {data.specialTerms
              .split("\n")
              .map((line) => line.trim())
              .filter((line) => line.length > 0)
              .map((line, index) => (
                <Text key={index} style={documentStyles.sectionValue}>
                  {line}
                </Text>
              ))}
          </View>
        )}

        <Text style={documentStyles.footer}>
          Ce contrat entre en vigueur à l&apos;activation du bail, après approbation par le
          locataire et versement intégral des dépôts initiaux convenus.
        </Text>
      </Page>
    </Document>
  );
}
