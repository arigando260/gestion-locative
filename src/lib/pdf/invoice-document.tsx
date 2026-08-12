// Template FIXE (V1), même principe que receipt-document.tsx — rendu
// UNIQUEMENT côté serveur (renderToBuffer, voir data/schedule-invoices.ts).
import { Document, Page, View, Text } from "@react-pdf/renderer";
import { documentStyles, DocumentHeader, type OrganizationHeaderInfo } from "./document-header";

export type InvoiceLineItem = {
  id: string;
  periodLabel: string;
  dueDate: string;
  amount: string;
};

export type InvoiceDocumentData = {
  organization: OrganizationHeaderInfo;
  tenantName: string;
  propertyLabel: string;
  invoiceReference: string;
  issuedDate: string;
  lineItems: InvoiceLineItem[];
  totalAmount: string;
};

// Contenu minimal demandé : coordonnées de l'organisation en en-tête,
// informations du locataire, détail des lignes (une par échéance), montant
// total — toujours scopée à un seul bail/réservation (voir Module 9), donc
// un seul locataire affiché ici, jamais une liste.
export function InvoiceDocument({ data }: { data: InvoiceDocumentData }) {
  return (
    <Document>
      <Page size="A4" style={documentStyles.page}>
        <DocumentHeader
          organization={data.organization}
          documentTitle="FACTURE"
          reference={data.invoiceReference}
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
        </View>

        <View style={documentStyles.table}>
          <View style={documentStyles.tableHeaderRow}>
            <Text style={[documentStyles.tableHeaderCell, documentStyles.colPeriod]}>
              Période
            </Text>
            <Text style={[documentStyles.tableHeaderCell, documentStyles.colDue]}>
              Échéance
            </Text>
            <Text style={[documentStyles.tableHeaderCell, documentStyles.colAmount]}>
              Montant
            </Text>
          </View>
          {data.lineItems.map((item) => (
            <View key={item.id} style={documentStyles.tableRow}>
              <Text style={[documentStyles.tableCell, documentStyles.colPeriod]}>
                {item.periodLabel}
              </Text>
              <Text style={[documentStyles.tableCell, documentStyles.colDue]}>
                {item.dueDate}
              </Text>
              <Text style={[documentStyles.tableCell, documentStyles.colAmount]}>
                {item.amount}
              </Text>
            </View>
          ))}
        </View>

        <View style={documentStyles.totalRow}>
          <Text style={documentStyles.totalLabel}>Total</Text>
          <Text style={documentStyles.totalValue}>{data.totalAmount}</Text>
        </View>

        <Text style={documentStyles.footer}>
          Facture générée pour les échéances listées ci-dessus.
        </Text>
      </Page>
    </Document>
  );
}
