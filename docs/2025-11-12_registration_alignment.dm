Title: Registro atómico alineado a DATABASE_SCHEMA.sql
Owner: Backend + App
Date: 2025-11-12

Objetivo
- Garantizar que, al registrar un usuario (auth.users), se creen de forma atómica y consistente:
  1) public.users (perfil mínimo)
  2) public.client_profiles (perfil de cliente)
  3) public.accounts (cuenta financiera tipo client)
- Alinear las RPCs con el esquema actualizado donde dirección y geolocalización viven en client_profiles.

Contexto
- DATABASE_SCHEMA.sql: public.users ya NO posee address/lat/lon/address_structured.
- Dirección y coordenadas residen en public.client_profiles.
- La app ya invoca ensure_user_profile_public tras signup; el fallo se debía a un desalineamiento de columnas en la RPC.

Plan de ejecución
1) Backend (SQL)
   - Ejecutar supabase_scripts/2025-11-12_20_FIX_registration_alignment.sql
     • Repara ensure_user_profile_public para que:
       - Inserte/actualice solo columnas válidas en public.users
       - Llame ensure_client_profile_and_account(p_user_id)
       - Si llegan address/lat/lon/address_structured, delega a update_client_default_address
     • Reemplaza create_user_profile_public como wrapper de ensure_user_profile_public
     • Asegura triggers:
       - AFTER INSERT en public.users -> ensure_client_profile_and_account
       - (Opcional) AFTER INSERT en auth.users -> ensure_user_profile_public
     • Limpieza: drops seguros de overloads para evitar 42P13

2) App (Flutter)
   - No se requiere cambio si la RPC se alinea. La app ya llama a:
     • ensure_user_profile_public durante signup
     • ensure_client_profile_and_account en la carga de sesión de clientes
     • update_client_default_address para persistir dirección cuando proceda
   - Opcional endurecimiento: validar tras signup que exista public.users y relanzar ensure si no aparece (ya contemplado en utilidades actuales).

3) Pruebas manuales
   - Caso 1: Registro email/password
     1. Registrar usuario desde la app.
     2. Verificar en DB:
        select * from public.users where id = '<NEW_UID>';
        select * from public.client_profiles where user_id = '<NEW_UID>';
        select * from public.accounts where user_id = '<NEW_UID>' and account_type='client';
     3. Si se envían address/lat/lon, confirmar que aparezcan en client_profiles.

   - Caso 2: OAuth (Google)
     1. Ingresar con Google desde la app.
     2. Verificar mismas 3 tablas.

   - Caso 3: Backfill idempotente
     1. Para un user en public.users sin client_profiles, insertar de prueba:
        insert into public.users(id, email, role) values ('<uid>', 'foo@bar.com', 'client');
     2. Verificar que el trigger generó client_profiles y accounts.

4) Rollback
   - Si se requiere volver a la versión previa, re-ejecutar el script 2025-10-21_fix_registration_rpcs.sql.
   - Nota: mantener coherencia con el esquema actual (sin address/lat/lon en users) para evitar errores.

Riesgos y mitigaciones
- Riesgo: auth.users no permite triggers en algunos proyectos.
  Mitigación: el trigger en auth es opcional; la app invoca RPC tras signup y el trigger en public.users asegura client_profiles/accounts.
- Riesgo: RLS impida upserts manuales.
  Mitigación: las RPCs son SECURITY DEFINER; usan funciones que bypass RLS controladamente.

Hecho / Criterios de aceptación
- Crear usuario nuevo desde app crea registro en public.users inmediatamente.
- Se crea client_profiles y cuenta financial 'client' sin intervención manual.
- No se referencian columnas inexistentes en public.users.
