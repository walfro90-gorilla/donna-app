# 🚀 DOÑA REPARTOS - BACKEND AI ARCHITECTURE BLUEPRINT
**Última actualización:** Marzo 2026
**Entorno:** UpCloud (Node.js/PM2) + Supabase + Next.js (CRM) + Flutter (App Móvil)

## 📌 Contexto para el Agente de Desarrollo Frontend (Flutter/Supabase)
Este documento describe la arquitectura actual del servidor de WhatsApp (Clawbot/Jimbot) que orquesta a la agente "Doña". **El servidor ya está desplegado, configurado y blindado en producción.** **⚠️ REGLA DE ORO PARA EL AGENTE FLUTTER:** NO es necesario levantar nuevos servidores Express ni abrir nuevos puertos para las notificaciones push de WhatsApp. El webhook `/notify` ya existe y está escuchando activamente en el puerto 3000. Tu único trabajo es disparar peticiones HTTP POST a este endpoint desde Supabase (Edge Functions o Triggers) cuando el estatus de una orden cambie.

---

## 🗺️ 1. Diagrama de Arquitectura (Mermaid)

\`\`\`mermaid
graph TD
    %% Entidades Externas
    WA[WhatsApp Cliente] <-->|Mensajes WA| NodeServer(Servidor UpCloud Node.js - Puerto 3000)
    Flutter[Flutter App / Repartidores] -->|Actualiza Estatus| Supabase[(Supabase DB)]
    NextCRM[Next.js CRM] <-->|Webhooks & Manual| NodeServer

    %% Servidor Node.js
    subgraph NodeServer [Orquestador Central - index.js]
        WA_Client[whatsapp-web.js]
        API_Express[Express API]
        Router[Router Cognitivo LLM]
        
        API_Express -->|/send| WA_Client
        API_Express -->|/notify| WA_Client
        WA_Client -->|Inbox Webhook| NextCRM
        WA_Client -->|Outbox Webhook| NextCRM
        WA_Client --> Router
    end

    %% Agentes IA
    subgraph Agents [Sistema Multi-Agente]
        Dona(Doña - dona.js <br> Delivery & Checkout)
        Gorilla(Gorilla - gorilla.js <br> B2B Afiliaciones)
        Ketzal(Ketzal - ketzal.js <br> B2E Repartidores)
        Jimbot(Jimbot <br> Fallback/Chat)
    end

    %% Flujo Interno
    Router -->|NLP Intent| Dona
    Router -->|NLP Intent| Gorilla
    Router -->|NLP Intent| Ketzal
    Router -->|Fallback| Jimbot

    %% Conexiones DB & Externas
    Dona <-->|Menú, Modificadores, Ordenes| Supabase
    Supabase -->|Trigger/Edge Function POST| API_Express
    Dona <-->|Geocoding Proxy| GoogleMaps[Google Maps API]
\`\`\`

---

## 🧠 2. El Orquestador Central (`index.js`)

El archivo principal actúa como el "Mothership". Mantiene la sesión de WhatsApp Web y rutea el tráfico.

### Funciones Principales:
* **Enrutamiento Cognitivo (GPT-4o-mini):** Analiza el `msg.body` entrante y decide si la intención es pedir comida (DOÑA), afiliar un restaurante (GORILLA), buscar empleo de repartidor (KETZAL) o solo charlar (JIMBOT).
* **Gestión de Sesiones:** Mantiene el estado en memoria (`sessions[phone]`) para que el usuario no pierda su carrito o paso de registro.
* **Kill-Switch (Human Handoff):** Envia un POST al CRM (Next.js) con el mensaje entrante. Si el CRM responde `autoRespond: false`, la IA se silencia para que un agente humano tome el control.
* **Registro B2C Dinámico:** Si un usuario nuevo interactúa, `index.js` intercepta la sesión, le pide Nombre, Correo y Dirección, valida la dirección vía Google Maps (Geofencing proxy en Supabase), crea una cuenta en `Supabase Auth` con contraseña generada automáticamente y lo guarda en `client_profiles` vía RPC `register_client_v2`.

### Endpoints Expuestos (Express en Puerto 3000):
* `POST /send`: Usado por el CRM para enviar mensajes manuales de agentes humanos.
* `POST /notify`: **[CRÍTICO PARA FLUTTER/SUPABASE]** Endpoint para notificaciones de estatus.

---

## 🌮 3. Agente Doña (`dona.js` - Delivery Engine)

El cerebro de las órdenes. Opera a través de una **Máquina de Estados de Lenguaje Natural (NLP State Machine)**.

### Características Clave:
1.  **Anti-Double-Taxation:** Lee los precios directamente de la base de datos (`products.price`). Asume que el restaurante ya incluyó su markup/comisión en el precio listado en la DB. No multiplica el precio por la comisión en tiempo real.
2.  **Modificadores Obligatorios y Opcionales:** Si un producto tiene `modifier_groups` en la DB, la IA pausa el carrito e inicia un flujo guiado (`COLLECTING_MODIFIERS`) haciendo preguntas de selección múltiple (ej. "¿Término de la carne?", "¿Extra de queso?"). Se procesa 100% en código duro para latencia cero.
3.  **NLP Checkout:** No depende de palabras clave exactas ("sí", "no", "correcto"). OpenAI evalúa todo el contexto del usuario (ej. "Simón, mándalo ahí") y transiciona los estados (`SAVE_NOTES`, `CONFIRM_ADDRESS`, `SET_PAYMENT`, `SUBMIT_ORDER`).
4.  **Generación de OTP (One Time Password):** Al cerrar la orden, extrae un `confirm_code` (o `pickup_code`) generado por la base de datos y se lo entrega al cliente para evitar fraudes en la entrega.
5.  **Memory Leak Protection:** Maneja limpiezas profundas de `setTimeout` en cada transición de estado para evitar que se envíen mensajes fantasma de "Se me quedó tu orden a medias".

---

## 🗄️ 4. Dependencias Críticas en Supabase (RPCs)

Para que el bot funcione, depende de estas funciones (RPCs) específicas ya implementadas en Supabase:

* `wa_create_order(p_user_id, p_restaurant_id, p_delivery_address, p_payment_method, p_order_notes, p_cash_amount, p_items, p_conversation_id)`: Guarda la orden maestra y sus items/modificadores en un solo hit transaccional. Retorna `order_id` y `pickup_code`.
* `get_product_with_modifiers(p_product_id)`: Devuelve un JSON anidado con los grupos de modificadores y opciones de un platillo.
* `check_location_coverage(p_lat, p_lon)`: Retorna el nombre de la zona si la ubicación entra en un polígono válido, o nulo si está fuera de cobertura.
* `get_client_total_debt(p_client_id)`: Para el Debt Blocker. Bloquea el uso de la IA si el cliente debe dinero.
* `has_active_couriers()`: Si devuelve `false`, Doña no toma el pedido.

---

## 🔌 5. Guía de Integración para el Agente Flutter/Supabase

### Webhook de Notificaciones Push (Estatus de Orden)
Cuando un repartidor en Flutter marque una orden como "En Camino", o la cocina como "Preparando", Supabase debe hacer un HTTP POST al servidor Node.js.

**Especificaciones del Request:**
* **URL:** `http://209.50.55.122:3000/notify`
* **Method:** `POST`
* **Headers:**
    * `Content-Type: application/json`
    * `x-bot-secret: 1f6499125071025b849aafb4992190583237e8886a8f409410c97aba6e6a84ea` *(Debe ser exacto a la variable de entorno `DONNA_BOT_SECRET`)*
* **Body (JSON):**
    ```json
    {
      "phone": "5215512345678",
      "message": "🔔 *Do