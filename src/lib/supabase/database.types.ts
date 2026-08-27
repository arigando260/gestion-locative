export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      countries: {
        Row: {
          code: string
          created_at: string
          is_active: boolean
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          is_active?: boolean
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          is_active?: boolean
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      deposit_ledger: {
        Row: {
          amount: number
          created_at: string
          deposit_type: string
          entry_type: string
          id: string
          imputation_category: string | null
          inspection_id: string | null
          lease_id: string | null
          maintenance_ticket_id: string | null
          organization_id: string
          payment_id: string | null
          payment_schedule_id: string | null
          reason: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          deposit_type: string
          entry_type: string
          id?: string
          imputation_category?: string | null
          inspection_id?: string | null
          lease_id?: string | null
          maintenance_ticket_id?: string | null
          organization_id: string
          payment_id?: string | null
          payment_schedule_id?: string | null
          reason?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          deposit_type?: string
          entry_type?: string
          id?: string
          imputation_category?: string | null
          inspection_id?: string | null
          lease_id?: string | null
          maintenance_ticket_id?: string | null
          organization_id?: string
          payment_id?: string | null
          payment_schedule_id?: string | null
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "deposit_ledger_inspection_org_fk"
            columns: ["organization_id", "inspection_id"]
            isOneToOne: false
            referencedRelation: "property_inspections"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "deposit_ledger_inspection_org_fk"
            columns: ["organization_id", "inspection_id"]
            isOneToOne: false
            referencedRelation: "property_inspections_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "deposit_ledger_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "deposit_ledger_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "deposit_ledger_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "deposit_ledger_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "deposit_ledger_maintenance_ticket_org_fk"
            columns: ["organization_id", "maintenance_ticket_id"]
            isOneToOne: false
            referencedRelation: "maintenance_tickets"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "deposit_ledger_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deposit_ledger_payment_org_fk"
            columns: ["organization_id", "payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "deposit_ledger_schedule_org_fk"
            columns: ["organization_id", "payment_schedule_id"]
            isOneToOne: false
            referencedRelation: "payment_schedules"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "deposit_ledger_schedule_org_fk"
            columns: ["organization_id", "payment_schedule_id"]
            isOneToOne: false
            referencedRelation: "payment_schedules_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      inspection_items: {
        Row: {
          condition: string
          created_at: string
          description: string | null
          estimated_repair_cost: number | null
          id: string
          inspection_id: string
          organization_id: string
          updated_at: string
          zone: string
        }
        Insert: {
          condition: string
          created_at?: string
          description?: string | null
          estimated_repair_cost?: number | null
          id?: string
          inspection_id: string
          organization_id: string
          updated_at?: string
          zone: string
        }
        Update: {
          condition?: string
          created_at?: string
          description?: string | null
          estimated_repair_cost?: number | null
          id?: string
          inspection_id?: string
          organization_id?: string
          updated_at?: string
          zone?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspection_items_inspection_org_fk"
            columns: ["organization_id", "inspection_id"]
            isOneToOne: false
            referencedRelation: "property_inspections"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "inspection_items_inspection_org_fk"
            columns: ["organization_id", "inspection_id"]
            isOneToOne: false
            referencedRelation: "property_inspections_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "inspection_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_photos: {
        Row: {
          file_hash: string
          id: string
          inspection_item_id: string
          organization_id: string
          storage_path: string
          uploaded_at: string
        }
        Insert: {
          file_hash: string
          id?: string
          inspection_item_id: string
          organization_id: string
          storage_path: string
          uploaded_at?: string
        }
        Update: {
          file_hash?: string
          id?: string
          inspection_item_id?: string
          organization_id?: string
          storage_path?: string
          uploaded_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspection_photos_item_org_fk"
            columns: ["organization_id", "inspection_item_id"]
            isOneToOne: false
            referencedRelation: "inspection_items"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "inspection_photos_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_schedule_items: {
        Row: {
          created_at: string
          id: string
          invoice_id: string
          organization_id: string
          payment_schedule_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          invoice_id: string
          organization_id: string
          payment_schedule_id: string
        }
        Update: {
          created_at?: string
          id?: string
          invoice_id?: string
          organization_id?: string
          payment_schedule_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoice_schedule_items_invoice_org_fk"
            columns: ["organization_id", "invoice_id"]
            isOneToOne: false
            referencedRelation: "schedule_invoices"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "invoice_schedule_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_schedule_items_schedule_org_fk"
            columns: ["organization_id", "payment_schedule_id"]
            isOneToOne: false
            referencedRelation: "payment_schedules"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "invoice_schedule_items_schedule_org_fk"
            columns: ["organization_id", "payment_schedule_id"]
            isOneToOne: false
            referencedRelation: "payment_schedules_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lease_advance_authorization_events: {
        Row: {
          action: string
          actor_id: string | null
          id: string
          lease_id: string
          occurred_at: string
          organization_id: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          id?: string
          lease_id: string
          occurred_at?: string
          organization_id: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          id?: string
          lease_id?: string
          occurred_at?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lease_advance_authorization_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lease_advance_events_actor_org_fk"
            columns: ["organization_id", "actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lease_advance_events_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lease_advance_events_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "lease_advance_events_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "lease_advance_events_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
        ]
      }
      lease_contracts: {
        Row: {
          approved_at: string | null
          first_viewed_at: string | null
          generated_at: string
          id: string
          lease_id: string
          organization_id: string
          storage_path: string
        }
        Insert: {
          approved_at?: string | null
          first_viewed_at?: string | null
          generated_at?: string
          id?: string
          lease_id: string
          organization_id: string
          storage_path: string
        }
        Update: {
          approved_at?: string | null
          first_viewed_at?: string | null
          generated_at?: string
          id?: string
          lease_id?: string
          organization_id?: string
          storage_path?: string
        }
        Relationships: [
          {
            foreignKeyName: "lease_contracts_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lease_contracts_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "lease_contracts_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "lease_contracts_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "lease_contracts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      lease_termination_requests: {
        Row: {
          cancelled_at: string | null
          created_at: string
          id: string
          initiated_by_staff_id: string | null
          initiated_by_tenant_id: string | null
          lease_id: string
          organization_id: string
          reason: string
          requested_end_date: string
          responded_at: string | null
          responded_by_staff_id: string | null
          responded_by_tenant_id: string | null
          response_note: string | null
          status: string
          updated_at: string
        }
        Insert: {
          cancelled_at?: string | null
          created_at?: string
          id?: string
          initiated_by_staff_id?: string | null
          initiated_by_tenant_id?: string | null
          lease_id: string
          organization_id: string
          reason: string
          requested_end_date: string
          responded_at?: string | null
          responded_by_staff_id?: string | null
          responded_by_tenant_id?: string | null
          response_note?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          cancelled_at?: string | null
          created_at?: string
          id?: string
          initiated_by_staff_id?: string | null
          initiated_by_tenant_id?: string | null
          lease_id?: string
          organization_id?: string
          reason?: string
          requested_end_date?: string
          responded_at?: string | null
          responded_by_staff_id?: string | null
          responded_by_tenant_id?: string | null
          response_note?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lease_termination_requests_initiated_tenant_fkey"
            columns: ["initiated_by_tenant_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lease_termination_requests_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lease_termination_requests_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "lease_termination_requests_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "lease_termination_requests_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "lease_termination_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lease_termination_requests_responded_staff_org_fk"
            columns: ["organization_id", "responded_by_staff_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lease_termination_requests_responded_tenant_fkey"
            columns: ["responded_by_tenant_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lease_termination_requests_staff_org_fk"
            columns: ["organization_id", "initiated_by_staff_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      leases: {
        Row: {
          advance_consumption_authorized: boolean
          advance_consumption_authorized_at: string | null
          advance_consumption_authorized_by: string | null
          billing_day: number | null
          created_at: string
          end_date: string | null
          id: string
          keys_returned_at: string | null
          organization_id: string
          payment_frequency: string
          payment_timing: string
          prepaid_rent_amount: number
          prepaid_rent_months: number
          property_id: string
          rent_amount: number
          security_deposit_amount: number
          security_deposit_months: number | null
          special_terms: string | null
          start_date: string
          status: string
          tenant_account_id: string
          tenant_capture_enabled: boolean | null
          updated_at: string
          utility_deposit_amount: number | null
        }
        Insert: {
          advance_consumption_authorized?: boolean
          advance_consumption_authorized_at?: string | null
          advance_consumption_authorized_by?: string | null
          billing_day?: number | null
          created_at?: string
          end_date?: string | null
          id?: string
          keys_returned_at?: string | null
          organization_id: string
          payment_frequency: string
          payment_timing: string
          prepaid_rent_amount?: number
          prepaid_rent_months?: number
          property_id: string
          rent_amount: number
          security_deposit_amount: number
          security_deposit_months?: number | null
          special_terms?: string | null
          start_date: string
          status?: string
          tenant_account_id: string
          tenant_capture_enabled?: boolean | null
          updated_at?: string
          utility_deposit_amount?: number | null
        }
        Update: {
          advance_consumption_authorized?: boolean
          advance_consumption_authorized_at?: string | null
          advance_consumption_authorized_by?: string | null
          billing_day?: number | null
          created_at?: string
          end_date?: string | null
          id?: string
          keys_returned_at?: string | null
          organization_id?: string
          payment_frequency?: string
          payment_timing?: string
          prepaid_rent_amount?: number
          prepaid_rent_months?: number
          property_id?: string
          rent_amount?: number
          security_deposit_amount?: number
          security_deposit_months?: number | null
          special_terms?: string | null
          start_date?: string
          status?: string
          tenant_account_id?: string
          tenant_capture_enabled?: boolean | null
          updated_at?: string
          utility_deposit_amount?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "leases_advance_authorized_by_org_fk"
            columns: ["organization_id", "advance_consumption_authorized_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "leases_advance_consumption_authorized_by_fkey"
            columns: ["advance_consumption_authorized_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leases_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leases_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "leases_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "leases_tenant_account_id_fkey"
            columns: ["tenant_account_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_ticket_photos: {
        Row: {
          file_hash: string
          id: string
          maintenance_ticket_id: string
          organization_id: string
          storage_path: string
          uploaded_at: string
        }
        Insert: {
          file_hash: string
          id?: string
          maintenance_ticket_id: string
          organization_id: string
          storage_path: string
          uploaded_at?: string
        }
        Update: {
          file_hash?: string
          id?: string
          maintenance_ticket_id?: string
          organization_id?: string
          storage_path?: string
          uploaded_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_ticket_photos_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_ticket_photos_ticket_org_fk"
            columns: ["organization_id", "maintenance_ticket_id"]
            isOneToOne: false
            referencedRelation: "maintenance_tickets"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      maintenance_tickets: {
        Row: {
          actual_cost: number | null
          created_at: string
          description: string | null
          estimated_cost: number | null
          id: string
          lease_id: string | null
          organization_id: string
          priority: string
          property_id: string
          reported_by_staff_id: string | null
          reported_by_tenant_id: string | null
          resolved_at: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          actual_cost?: number | null
          created_at?: string
          description?: string | null
          estimated_cost?: number | null
          id?: string
          lease_id?: string | null
          organization_id: string
          priority?: string
          property_id: string
          reported_by_staff_id?: string | null
          reported_by_tenant_id?: string | null
          resolved_at?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          actual_cost?: number | null
          created_at?: string
          description?: string | null
          estimated_cost?: number | null
          id?: string
          lease_id?: string | null
          organization_id?: string
          priority?: string
          property_id?: string
          reported_by_staff_id?: string | null
          reported_by_tenant_id?: string | null
          resolved_at?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_tickets_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "maintenance_tickets_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "maintenance_tickets_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "maintenance_tickets_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "maintenance_tickets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_tickets_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "maintenance_tickets_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "maintenance_tickets_reported_by_staff_org_fk"
            columns: ["organization_id", "reported_by_staff_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "maintenance_tickets_reported_by_tenant_fkey"
            columns: ["reported_by_tenant_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_subscriptions: {
        Row: {
          created_at: string
          current_period_end: string | null
          current_period_start: string | null
          id: string
          organization_id: string
          plan_id: string
          status: string
          trial_ends_at: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          organization_id: string
          plan_id: string
          status?: string
          trial_ends_at?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          organization_id?: string
          plan_id?: string
          status?: string
          trial_ends_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_subscriptions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "subscription_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          address: string | null
          country_code: string
          created_at: string
          default_billing_day: number | null
          default_standard_check_in_time: string | null
          default_standard_check_out_time: string | null
          default_turnover_buffer_days: number
          email: string | null
          id: string
          is_active: boolean
          name: string
          organization_type: string | null
          phone: string | null
          slug: string
          special_terms: string | null
          tenant_capture_enabled: boolean
          updated_at: string
        }
        Insert: {
          address?: string | null
          country_code: string
          created_at?: string
          default_billing_day?: number | null
          default_standard_check_in_time?: string | null
          default_standard_check_out_time?: string | null
          default_turnover_buffer_days?: number
          email?: string | null
          id?: string
          is_active?: boolean
          name: string
          organization_type?: string | null
          phone?: string | null
          slug: string
          special_terms?: string | null
          tenant_capture_enabled?: boolean
          updated_at?: string
        }
        Update: {
          address?: string | null
          country_code?: string
          created_at?: string
          default_billing_day?: number | null
          default_standard_check_in_time?: string | null
          default_standard_check_out_time?: string | null
          default_turnover_buffer_days?: number
          email?: string | null
          id?: string
          is_active?: boolean
          name?: string
          organization_type?: string | null
          phone?: string | null
          slug?: string
          special_terms?: string | null
          tenant_capture_enabled?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organizations_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
        ]
      }
      payment_receipts: {
        Row: {
          created_at: string
          generated_at: string | null
          id: string
          organization_id: string
          payment_id: string
          storage_path: string | null
        }
        Insert: {
          created_at?: string
          generated_at?: string | null
          id?: string
          organization_id: string
          payment_id: string
          storage_path?: string | null
        }
        Update: {
          created_at?: string
          generated_at?: string | null
          id?: string
          organization_id?: string
          payment_id?: string
          storage_path?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_receipts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_receipts_payment_org_fk"
            columns: ["organization_id", "payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      payment_schedules: {
        Row: {
          amount_due: number
          created_at: string
          due_date: string
          id: string
          is_partial_period: boolean
          lease_id: string | null
          organization_id: string
          period_end_date: string
          period_start_date: string
          status: string
          updated_at: string
        }
        Insert: {
          amount_due: number
          created_at?: string
          due_date: string
          id?: string
          is_partial_period?: boolean
          lease_id?: string | null
          organization_id: string
          period_end_date: string
          period_start_date: string
          status?: string
          updated_at?: string
        }
        Update: {
          amount_due?: number
          created_at?: string
          due_date?: string
          id?: string
          is_partial_period?: boolean
          lease_id?: string | null
          organization_id?: string
          period_end_date?: string
          period_start_date?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_schedules_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "payment_schedules_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payment_schedules_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payment_schedules_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payment_schedules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      payments: {
        Row: {
          amount: number
          created_at: string
          direction: string
          external_reference: string | null
          id: string
          lease_id: string | null
          method: string
          organization_id: string
          payment_date: string
          payment_schedule_id: string | null
          payment_type: string
          status: string
          updated_at: string
        }
        Insert: {
          amount: number
          created_at?: string
          direction: string
          external_reference?: string | null
          id?: string
          lease_id?: string | null
          method: string
          organization_id: string
          payment_date?: string
          payment_schedule_id?: string | null
          payment_type: string
          status?: string
          updated_at?: string
        }
        Update: {
          amount?: number
          created_at?: string
          direction?: string
          external_reference?: string | null
          id?: string
          lease_id?: string | null
          method?: string
          organization_id?: string
          payment_date?: string
          payment_schedule_id?: string | null
          payment_type?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "payments_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payments_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payments_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_schedule_org_fk"
            columns: ["organization_id", "payment_schedule_id"]
            isOneToOne: false
            referencedRelation: "payment_schedules"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "payments_schedule_org_fk"
            columns: ["organization_id", "payment_schedule_id"]
            isOneToOne: false
            referencedRelation: "payment_schedules_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      permissions: {
        Row: {
          action: string
          description: string | null
          resource: string
        }
        Insert: {
          action: string
          description?: string | null
          resource: string
        }
        Update: {
          action?: string
          description?: string | null
          resource?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          email: string
          full_name: string | null
          id: string
          is_active: boolean
          organization_id: string
          phone: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          full_name?: string | null
          id: string
          is_active?: boolean
          organization_id: string
          phone?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          is_active?: boolean
          organization_id?: string
          phone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      properties: {
        Row: {
          address_complement: string | null
          city: string | null
          country_code: string | null
          created_at: string
          external_owner_id: string | null
          id: string
          location_type: string
          name: string
          neighborhood: string | null
          organization_id: string
          price: number
          standard_check_in_time: string | null
          standard_check_out_time: string | null
          status: string
          turnover_buffer_days: number | null
          updated_at: string
        }
        Insert: {
          address_complement?: string | null
          city?: string | null
          country_code?: string | null
          created_at?: string
          external_owner_id?: string | null
          id?: string
          location_type: string
          name: string
          neighborhood?: string | null
          organization_id: string
          price: number
          standard_check_in_time?: string | null
          standard_check_out_time?: string | null
          status?: string
          turnover_buffer_days?: number | null
          updated_at?: string
        }
        Update: {
          address_complement?: string | null
          city?: string | null
          country_code?: string | null
          created_at?: string
          external_owner_id?: string | null
          id?: string
          location_type?: string
          name?: string
          neighborhood?: string | null
          organization_id?: string
          price?: number
          standard_check_in_time?: string | null
          standard_check_out_time?: string | null
          status?: string
          turnover_buffer_days?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "properties_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "properties_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      property_agent_assignments: {
        Row: {
          agent_id: string
          assigned_at: string
          assigned_by: string
          id: string
          organization_id: string
          property_id: string
        }
        Insert: {
          agent_id: string
          assigned_at?: string
          assigned_by: string
          id?: string
          organization_id: string
          property_id: string
        }
        Update: {
          agent_id?: string
          assigned_at?: string
          assigned_by?: string
          id?: string
          organization_id?: string
          property_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "property_agent_assignments_agent_org_fk"
            columns: ["organization_id", "agent_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "property_agent_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "property_agent_assignments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "property_agent_assignments_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "property_agent_assignments_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      property_inspections: {
        Row: {
          conducted_by: string | null
          created_at: string
          created_by_tenant: boolean
          document_status: string
          finalized_at: string | null
          id: string
          inspection_date: string
          inspection_type: string
          lease_id: string | null
          observations: string | null
          organization_id: string
          tenant_comments: string | null
          tenant_validation_at: string | null
          tenant_validation_status: string
          updated_at: string
        }
        Insert: {
          conducted_by?: string | null
          created_at?: string
          created_by_tenant?: boolean
          document_status?: string
          finalized_at?: string | null
          id?: string
          inspection_date: string
          inspection_type: string
          lease_id?: string | null
          observations?: string | null
          organization_id: string
          tenant_comments?: string | null
          tenant_validation_at?: string | null
          tenant_validation_status?: string
          updated_at?: string
        }
        Update: {
          conducted_by?: string | null
          created_at?: string
          created_by_tenant?: boolean
          document_status?: string
          finalized_at?: string | null
          id?: string
          inspection_date?: string
          inspection_type?: string
          lease_id?: string | null
          observations?: string | null
          organization_id?: string
          tenant_comments?: string | null
          tenant_validation_at?: string | null
          tenant_validation_status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "property_inspections_conducted_by_org_fk"
            columns: ["organization_id", "conducted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "property_inspections_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "property_inspections_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "property_inspections_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "property_inspections_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "property_inspections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      property_types: {
        Row: {
          code: string
          created_at: string
          id: string
          name: string
          organization_id: string | null
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          name: string
          organization_id?: string | null
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          name?: string
          organization_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "property_types_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          action: string
          created_at: string
          resource: string
          role_id: string
        }
        Insert: {
          action: string
          created_at?: string
          resource: string
          role_id: string
        }
        Update: {
          action?: string
          created_at?: string
          resource?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_resource_action_fkey"
            columns: ["resource", "action"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["resource", "action"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_system: boolean
          name: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          id?: string
          is_system?: boolean
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_system?: boolean
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "roles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      schedule_invoices: {
        Row: {
          generated_at: string
          generated_by: string
          id: string
          lease_id: string | null
          organization_id: string
          storage_path: string
        }
        Insert: {
          generated_at?: string
          generated_by: string
          id?: string
          lease_id?: string | null
          organization_id: string
          storage_path: string
        }
        Update: {
          generated_at?: string
          generated_by?: string
          id?: string
          lease_id?: string | null
          organization_id?: string
          storage_path?: string
        }
        Relationships: [
          {
            foreignKeyName: "schedule_invoices_generated_by_org_fk"
            columns: ["organization_id", "generated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "schedule_invoices_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "schedule_invoices_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "schedule_invoices_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "schedule_invoices_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "schedule_invoices_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          organization_id: string
          role_code: string
          status: string
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by: string
          organization_id: string
          role_code: string
          status?: string
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string
          organization_id?: string
          role_code?: string
          status?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_invitations_accepted_by_fkey"
            columns: ["accepted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_plans: {
        Row: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          max_properties: number | null
          monthly_price: number
          name: string
          sort_order: number
          trial_days: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          max_properties?: number | null
          monthly_price: number
          name: string
          sort_order?: number
          trial_days?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          max_properties?: number | null
          monthly_price?: number
          name?: string
          sort_order?: number
          trial_days?: number
          updated_at?: string
        }
        Relationships: []
      }
      tenant_accounts: {
        Row: {
          created_at: string
          email: string
          full_name: string | null
          id: string
          is_active: boolean
          phone: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          full_name?: string | null
          id: string
          is_active?: boolean
          phone?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          is_active?: boolean
          phone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      tenant_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          organization_id: string
          status: string
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by: string
          organization_id: string
          status?: string
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string
          organization_id?: string
          status?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_invitations_accepted_by_fkey"
            columns: ["accepted_by"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_organization_memberships: {
        Row: {
          created_at: string
          id: string
          organization_id: string
          status: string
          tenant_account_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          organization_id: string
          status?: string
          tenant_account_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          organization_id?: string
          status?: string
          tenant_account_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_organization_memberships_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_organization_memberships_tenant_account_id_fkey"
            columns: ["tenant_account_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          role_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          role_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          role_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      deposit_ledger_balances: {
        Row: {
          amount_held: number | null
          balance: number | null
          deposit_type: string | null
          lease_id: string | null
          organization_id: string | null
          total_imputed: number | null
          total_refunded: number | null
        }
        Relationships: [
          {
            foreignKeyName: "deposit_ledger_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "deposit_ledger_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "deposit_ledger_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "deposit_ledger_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "deposit_ledger_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leases_activation_readiness: {
        Row: {
          contract_approved_at: string | null
          contract_first_viewed_at: string | null
          contract_generated_at: string | null
          contract_id: string | null
          contract_storage_path: string | null
          deposits_complete: boolean | null
          lease_id: string | null
          organization_id: string | null
          status: string | null
        }
        Relationships: [
          {
            foreignKeyName: "leases_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leases_closure_status: {
        Row: {
          closure_reference_date: string | null
          entry_inspection_done: boolean | null
          exit_inspection_done: boolean | null
          exit_inspection_due_date: string | null
          keys_returned_at: string | null
          latest_finalized_entry_inspection_date: string | null
          latest_finalized_entry_inspection_id: string | null
          latest_finalized_exit_inspection_date: string | null
          latest_finalized_exit_inspection_id: string | null
          lease_end_date: string | null
          lease_id: string | null
          organization_id: string | null
          property_id: string | null
          property_name: string | null
          status: string | null
          tenant_account_id: string | null
          tenant_full_name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "leases_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leases_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "leases_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "leases_tenant_account_id_fkey"
            columns: ["tenant_account_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      leases_schedule_coverage: {
        Row: {
          coverage_end_date: string | null
          lease_end_date: string | null
          lease_id: string | null
          organization_id: string | null
          property_id: string | null
          property_name: string | null
          status: string | null
          tenant_account_id: string | null
          tenant_full_name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "leases_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leases_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "leases_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties_effective_status"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "leases_tenant_account_id_fkey"
            columns: ["tenant_account_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      my_permissions: {
        Row: {
          action: string | null
          resource: string | null
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_resource_action_fkey"
            columns: ["resource", "action"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["resource", "action"]
          },
        ]
      }
      payment_schedules_effective_status: {
        Row: {
          amount_due: number | null
          covered_amount: number | null
          created_at: string | null
          due_date: string | null
          effective_status: string | null
          id: string | null
          is_partial_period: boolean | null
          lease_id: string | null
          organization_id: string | null
          period_end_date: string | null
          period_start_date: string | null
          status: string | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_schedules_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "payment_schedules_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payment_schedules_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payment_schedules_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "payment_schedules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      properties_effective_status: {
        Row: {
          address_complement: string | null
          city: string | null
          country_code: string | null
          created_at: string | null
          effective_status: string | null
          external_owner_id: string | null
          id: string | null
          location_type: string | null
          name: string | null
          neighborhood: string | null
          organization_id: string | null
          price: number | null
          standard_check_in_time: string | null
          standard_check_out_time: string | null
          status: string | null
          turnover_buffer_days: number | null
          updated_at: string | null
        }
        Insert: {
          address_complement?: string | null
          city?: string | null
          country_code?: string | null
          created_at?: string | null
          effective_status?: never
          external_owner_id?: string | null
          id?: string | null
          location_type?: string | null
          name?: string | null
          neighborhood?: string | null
          organization_id?: string | null
          price?: number | null
          standard_check_in_time?: string | null
          standard_check_out_time?: string | null
          status?: string | null
          turnover_buffer_days?: number | null
          updated_at?: string | null
        }
        Update: {
          address_complement?: string | null
          city?: string | null
          country_code?: string | null
          created_at?: string | null
          effective_status?: never
          external_owner_id?: string | null
          id?: string | null
          location_type?: string | null
          name?: string | null
          neighborhood?: string | null
          organization_id?: string | null
          price?: number | null
          standard_check_in_time?: string | null
          standard_check_out_time?: string | null
          status?: string | null
          turnover_buffer_days?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "properties_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "properties_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      property_inspections_effective_status: {
        Row: {
          conducted_by: string | null
          created_at: string | null
          created_by_tenant: boolean | null
          document_status: string | null
          effective_validation_status: string | null
          finalized_at: string | null
          id: string | null
          inspection_date: string | null
          inspection_type: string | null
          lease_id: string | null
          observations: string | null
          organization_id: string | null
          tenant_comments: string | null
          tenant_validation_at: string | null
          tenant_validation_status: string | null
          updated_at: string | null
        }
        Insert: {
          conducted_by?: string | null
          created_at?: string | null
          created_by_tenant?: boolean | null
          document_status?: string | null
          effective_validation_status?: never
          finalized_at?: string | null
          id?: string | null
          inspection_date?: string | null
          inspection_type?: string | null
          lease_id?: string | null
          observations?: string | null
          organization_id?: string | null
          tenant_comments?: string | null
          tenant_validation_at?: string | null
          tenant_validation_status?: string | null
          updated_at?: string | null
        }
        Update: {
          conducted_by?: string | null
          created_at?: string | null
          created_by_tenant?: boolean | null
          document_status?: string | null
          effective_validation_status?: never
          finalized_at?: string | null
          id?: string | null
          inspection_date?: string | null
          inspection_type?: string | null
          lease_id?: string | null
          observations?: string | null
          organization_id?: string | null
          tenant_comments?: string | null
          tenant_validation_at?: string | null
          tenant_validation_status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "property_inspections_conducted_by_org_fk"
            columns: ["organization_id", "conducted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "property_inspections_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "property_inspections_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_activation_readiness"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "property_inspections_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_closure_status"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "property_inspections_lease_org_fk"
            columns: ["organization_id", "lease_id"]
            isOneToOne: false
            referencedRelation: "leases_schedule_coverage"
            referencedColumns: ["organization_id", "lease_id"]
          },
          {
            foreignKeyName: "property_inspections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      accept_tenant_invitation_existing_account: {
        Args: { p_token: string }
        Returns: undefined
      }
      check_staff_invitation_existing_account: {
        Args: { p_token: string }
        Returns: boolean
      }
      check_tenant_invitation_existing_account: {
        Args: { p_token: string }
        Returns: boolean
      }
      create_property: {
        Args: {
          p_address_complement: string
          p_city: string
          p_country_code: string
          p_location_type: string
          p_name: string
          p_neighborhood: string
          p_organization_id: string
          p_price: number
        }
        Returns: {
          address_complement: string | null
          city: string | null
          country_code: string | null
          created_at: string
          external_owner_id: string | null
          id: string
          location_type: string
          name: string
          neighborhood: string | null
          organization_id: string
          price: number
          standard_check_in_time: string | null
          standard_check_out_time: string | null
          status: string
          turnover_buffer_days: number | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "properties"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      delete_lease_with_contract: {
        Args: { p_lease_id: string }
        Returns: undefined
      }
      generate_payment_schedules_for_lease: {
        Args: {
          p_horizon_months?: number
          p_lease_id: string
          p_prepaid_payment_method?: string
        }
        Returns: number
      }
      get_staff_invitation_preview: {
        Args: { p_token: string }
        Returns: {
          email: string
          expires_at: string
          organization_name: string
          role_code: string
          status: string
        }[]
      }
      get_tenant_invitation_preview: {
        Args: { p_token: string }
        Returns: {
          email: string
          expires_at: string
          organization_name: string
          status: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
