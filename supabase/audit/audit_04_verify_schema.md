[
  {
    "step": "6_FOREIGN_KEYS",
    "table_schema": "public",
    "table_name": "client_profiles",
    "column_name": "user_id",
    "foreign_table_schema": "public",
    "foreign_table_name": "users",
    "foreign_column_name": "id",
    "constraint_name": "client_profiles_user_id_fkey"
  },
  {
    "step": "6_FOREIGN_KEYS",
    "table_schema": "public",
    "table_name": "delivery_agent_profiles",
    "column_name": "user_id",
    "foreign_table_schema": "public",
    "foreign_table_name": "users",
    "foreign_column_name": "id",
    "constraint_name": "delivery_agent_profiles_user_id_fkey"
  },
  {
    "step": "6_FOREIGN_KEYS",
    "table_schema": "public",
    "table_name": "restaurants",
    "column_name": "user_id",
    "foreign_table_schema": "public",
    "foreign_table_name": "users",
    "foreign_column_name": "id",
    "constraint_name": "restaurants_user_id_fkey"
  }
]