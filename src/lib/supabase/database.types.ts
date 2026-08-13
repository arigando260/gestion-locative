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
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
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
          organization_id: string
          payment_id: string | null
          payment_schedule_id: string | null
          reason: string | null
          reservation_id: string | null
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
          organization_id: string
          payment_id?: string | null
          payment_schedule_id?: string | null
          reason?: string | null
          reservation_id?: string | null
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
          organization_id?: string
          payment_id?: string | null
          payment_schedule_id?: string | null
          reason?: string | null
          reservation_id?: string | null
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
            foreignKeyName: "deposit_ledger_reservation_org_fk"
            columns: ["organization_id", "reservation_id"]
            isOneToOne: false
            referencedRelation: "reservations"
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
            foreignKeyName: "leases_tenant_account_id_fkey"
            columns: ["tenant_account_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          default_billing_day: number | null
          default_standard_check_in_time: string | null
          default_standard_check_out_time: string | null
          default_turnover_buffer_days: number
          id: string
          is_active: boolean
          name: string
          slug: string
          tenant_capture_enabled: boolean
          updated_at: string
        }
        Insert: {
          created_at?: string
          default_billing_day?: number | null
          default_standard_check_in_time?: string | null
          default_standard_check_out_time?: string | null
          default_turnover_buffer_days?: number
          id?: string
          is_active?: boolean
          name: string
          slug: string
          tenant_capture_enabled?: boolean
          updated_at?: string
        }
        Update: {
          created_at?: string
          default_billing_day?: number | null
          default_standard_check_in_time?: string | null
          default_standard_check_out_time?: string | null
          default_turnover_buffer_days?: number
          id?: string
          is_active?: boolean
          name?: string
          slug?: string
          tenant_capture_enabled?: boolean
          updated_at?: string
        }
        Relationships: []
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
          reservation_id: string | null
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
          reservation_id?: string | null
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
          reservation_id?: string | null
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
            foreignKeyName: "payment_schedules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_schedules_reservation_org_fk"
            columns: ["organization_id", "reservation_id"]
            isOneToOne: false
            referencedRelation: "reservations"
            referencedColumns: ["organization_id", "id"]
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
          reservation_id: string | null
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
          reservation_id?: string | null
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
          reservation_id?: string | null
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
            foreignKeyName: "payments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_reservation_org_fk"
            columns: ["organization_id", "reservation_id"]
            isOneToOne: false
            referencedRelation: "reservations"
            referencedColumns: ["organization_id", "id"]
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
          address: string
          created_at: string
          external_owner_id: string | null
          id: string
          location_type: string
          name: string
          organization_id: string
          price: number
          standard_check_in_time: string | null
          standard_check_out_time: string | null
          status: string
          turnover_buffer_days: number | null
          updated_at: string
        }
        Insert: {
          address: string
          created_at?: string
          external_owner_id?: string | null
          id?: string
          location_type: string
          name: string
          organization_id: string
          price: number
          standard_check_in_time?: string | null
          standard_check_out_time?: string | null
          status?: string
          turnover_buffer_days?: number | null
          updated_at?: string
        }
        Update: {
          address?: string
          created_at?: string
          external_owner_id?: string | null
          id?: string
          location_type?: string
          name?: string
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
            foreignKeyName: "properties_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
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
          reservation_id: string | null
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
          reservation_id?: string | null
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
          reservation_id?: string | null
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
            foreignKeyName: "property_inspections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "property_inspections_reservation_org_fk"
            columns: ["organization_id", "reservation_id"]
            isOneToOne: false
            referencedRelation: "reservations"
            referencedColumns: ["organization_id", "id"]
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
      reservations: {
        Row: {
          check_in_date: string
          check_out_date: string
          created_at: string
          id: string
          nightly_rate: number
          organization_id: string
          property_id: string
          status: string
          tenant_account_id: string
          total_amount: number
          turnover_buffer_days: number
          updated_at: string
        }
        Insert: {
          check_in_date: string
          check_out_date: string
          created_at?: string
          id?: string
          nightly_rate: number
          organization_id: string
          property_id: string
          status?: string
          tenant_account_id: string
          total_amount: number
          turnover_buffer_days: number
          updated_at?: string
        }
        Update: {
          check_in_date?: string
          check_out_date?: string
          created_at?: string
          id?: string
          nightly_rate?: number
          organization_id?: string
          property_id?: string
          status?: string
          tenant_account_id?: string
          total_amount?: number
          turnover_buffer_days?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "reservations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reservations_property_org_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "reservations_tenant_account_id_fkey"
            columns: ["tenant_account_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
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
          reservation_id: string | null
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
            foreignKeyName: "deposit_ledger_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deposit_ledger_reservation_org_fk"
            columns: ["organization_id", "reservation_id"]
            isOneToOne: false
            referencedRelation: "reservations"
            referencedColumns: ["organization_id", "id"]
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
            foreignKeyName: "leases_tenant_org_fk"
            columns: ["organization_id", "tenant_account_id"]
            isOneToOne: false
            referencedRelation: "tenant_accounts"
            referencedColumns: ["organization_id", "id"]
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
          reservation_id: string | null
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
            foreignKeyName: "payment_schedules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_schedules_reservation_org_fk"
            columns: ["organization_id", "reservation_id"]
            isOneToOne: false
            referencedRelation: "reservations"
            referencedColumns: ["organization_id", "id"]
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
          reservation_id: string | null
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
          reservation_id?: string | null
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
          reservation_id?: string | null
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
            foreignKeyName: "property_inspections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "property_inspections_reservation_org_fk"
            columns: ["organization_id", "reservation_id"]
            isOneToOne: false
            referencedRelation: "reservations"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
    }
    Functions: {
      generate_payment_schedules_for_lease: {
        Args: {
          p_horizon_months?: number
          p_lease_id: string
          p_prepaid_payment_method?: string
        }
        Returns: number
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
