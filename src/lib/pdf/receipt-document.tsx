// Template FIXE (V1) — pas d'éditeur, pas de personnalisation. Rendu
// UNIQUEMENT côté serveur (renderToBuffer, voir data/payment-receipts.ts) :
// ce fichier n'est jamais importé dans un arbre React rendu au navigateur.
import { Document, Page, View, Text } from "@react-pdf/renderer";
import { documentStyles, DocumentHeader, type OrganizationHeaderInfo } from "./document-header";

export type ReceiptDocumentData = {
  organization: OrganizationHeaderInfo;
  tenantName: string;
  amount: string;
  paymentDate: string;
  methodLabel: string;
  scheduleReference: string;
  receiptReference: string;
};

// Contenu minimal demandé : coordonnées de l'organisation, nom du
// locataire, montant, date, moyen de paiement, référence de l'échéance
// concernée — rien de plus en V1.
export function ReceiptDocument({ data }: { data: ReceiptDocumentData }) {
  return (
    <Document>
      <Page size="A4" style={documentStyles.page}>
        <DocumentHeader
          organization={data.organization}
          documentTitle="REÇU DE PAIEMENT"
          reference={data.receiptReference}
          date={data.paymentDate}
        />
        <View style={documentStyles.divider} />

        <View style={documentStyles.section}>
          <Text style={documentStyles.sectionLabel}>Locataire</Text>
          <Text style={documentStyles.sectionValue}>{data.tenantName}</Text>
        </View>

        <View style={documentStyles.section}>
          <Text style={documentStyles.sectionLabel}>Échéance concernée</Text>
          <Text style={documentStyles.sectionValue}>{data.scheduleReference}</Text>
        </View>

        <View style={documentStyles.section}>
          <Text style={documentStyles.sectionLabel}>Moyen de paiement</Text>
          <Text style={documentStyles.sectionValue}>{data.methodLabel}</Text>
        </View>

        <View style={documentStyles.totalRow}>
          <Text style={documentStyles.totalLabel}>Montant reçu</Text>
          <Text style={documentStyles.totalValue}>{data.amount}</Text>
        </View>

        <Text style={documentStyles.footer}>
          Ce reçu atteste la réception du paiement décrit ci-dessus.
        </Text>
      </Page>
    </Document>
  );
}
