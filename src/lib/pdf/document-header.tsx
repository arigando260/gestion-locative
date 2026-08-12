// Styles et en-tête partagés entre receipt-document.tsx et
// invoice-document.tsx — les deux documents affichent exactement le même
// bloc "coordonnées de l'organisation", jamais dupliqué à la main.
//
// Limite connue acceptée (V1) : libellés en français uniquement, quel que
// soit le paramètre de langue du destinataire — même limite déjà acceptée
// pour les messages métier RAISE EXCEPTION (voir ARCHITECTURE.md). Localiser
// le rendu PDF demanderait de faire transiter la locale à travers tout le
// pipeline de génération, hors périmètre de cette tranche.
import { StyleSheet, View, Text } from "@react-pdf/renderer";

export const documentStyles = StyleSheet.create({
  page: {
    padding: 40,
    fontSize: 10,
    fontFamily: "Helvetica",
    color: "#1a1a1a",
  },
  headerRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    marginBottom: 24,
  },
  orgBlock: {
    flexDirection: "column",
    gap: 2,
  },
  orgName: {
    fontSize: 14,
    fontFamily: "Helvetica-Bold",
    marginBottom: 4,
  },
  orgDetail: {
    fontSize: 9,
    color: "#555555",
  },
  titleBlock: {
    flexDirection: "column",
    alignItems: "flex-end",
    gap: 2,
  },
  documentTitle: {
    fontSize: 16,
    fontFamily: "Helvetica-Bold",
    marginBottom: 4,
  },
  divider: {
    borderBottomWidth: 1,
    borderBottomColor: "#cccccc",
    marginBottom: 16,
  },
  section: {
    marginBottom: 16,
  },
  sectionLabel: {
    fontSize: 9,
    color: "#555555",
    marginBottom: 2,
  },
  sectionValue: {
    fontSize: 11,
  },
  table: {
    marginTop: 8,
    marginBottom: 16,
  },
  tableHeaderRow: {
    flexDirection: "row",
    borderBottomWidth: 1,
    borderBottomColor: "#1a1a1a",
    paddingBottom: 4,
    marginBottom: 4,
  },
  tableRow: {
    flexDirection: "row",
    borderBottomWidth: 1,
    borderBottomColor: "#eeeeee",
    paddingVertical: 4,
  },
  tableHeaderCell: {
    fontSize: 9,
    fontFamily: "Helvetica-Bold",
  },
  tableCell: {
    fontSize: 10,
  },
  colPeriod: { width: "55%" },
  colDue: { width: "20%" },
  colAmount: { width: "25%", textAlign: "right" },
  totalRow: {
    flexDirection: "row",
    justifyContent: "flex-end",
    marginTop: 8,
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: "#1a1a1a",
  },
  totalLabel: {
    fontSize: 11,
    fontFamily: "Helvetica-Bold",
    marginRight: 12,
  },
  totalValue: {
    fontSize: 11,
    fontFamily: "Helvetica-Bold",
  },
  footer: {
    position: "absolute",
    bottom: 30,
    left: 40,
    right: 40,
    fontSize: 8,
    color: "#999999",
    textAlign: "center",
  },
});

export type OrganizationHeaderInfo = {
  name: string;
  address: string | null;
  phone: string | null;
  email: string | null;
};

export function DocumentHeader({
  organization,
  documentTitle,
  reference,
  date,
}: {
  organization: OrganizationHeaderInfo;
  documentTitle: string;
  reference: string;
  date: string;
}) {
  return (
    <View style={documentStyles.headerRow}>
      <View style={documentStyles.orgBlock}>
        <Text style={documentStyles.orgName}>{organization.name}</Text>
        {organization.address && (
          <Text style={documentStyles.orgDetail}>{organization.address}</Text>
        )}
        {organization.phone && (
          <Text style={documentStyles.orgDetail}>{organization.phone}</Text>
        )}
        {organization.email && (
          <Text style={documentStyles.orgDetail}>{organization.email}</Text>
        )}
      </View>
      <View style={documentStyles.titleBlock}>
        <Text style={documentStyles.documentTitle}>{documentTitle}</Text>
        <Text style={documentStyles.orgDetail}>{reference}</Text>
        <Text style={documentStyles.orgDetail}>{date}</Text>
      </View>
    </View>
  );
}
