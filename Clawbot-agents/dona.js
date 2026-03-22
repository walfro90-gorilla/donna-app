const crypto = require('crypto');
const axios = require('axios');

// 🔍 Fuzzy product matcher — evita fallos por plurales, acentos o abreviaciones
// Prioridades: exact > starts-with > cross-includes > any-word-match
function findProductInMenu(menu, requestedName) {
    const norm = s => s.trim().toLowerCase()
        .normalize('NFD').replace(/[\u0300-\u036f]/g, ''); // quitar acentos

    const rn = norm(requestedName);

    // P1: Coincidencia exacta
    let m = menu.find(p => norm(p.name) === rn);
    if (m) return m;

    // P2: El nombre del menú empieza con lo pedido (ej. "Boneless 250gr" startsWith "boneless")
    m = menu.find(p => norm(p.name).startsWith(rn));
    if (m) return m;

    // P3: Lo pedido empieza con el nombre del menú (ej. "sodas" startsWith "soda" del menú "Soda")
    //     También cubre plurales: menú "Soda" → pedido "Sodas"
    m = menu.find(p => rn.startsWith(norm(p.name)));
    if (m) return m;

    // P4: Contención bidireccional (ej. menú "Sodas" contiene "soda")
    m = menu.find(p => norm(p.name).includes(rn) || rn.includes(norm(p.name)));
    if (m) return m;

    // P5: Coincidencia por primera palabra del menú (ej. "hamburguesa" vs "Hamburguesa Sirloin")
    m = menu.find(p => {
        const firstWord = norm(p.name).split(' ')[0];
        return firstWord === rn || rn.startsWith(firstWord) || firstWord.startsWith(rn);
    });
    return m || null;
}

// 🛠️ Función Helper: Calcula los totales de la orden en memoria
function calculateTotals(session) {
    let subtotal = 0;
    if (session.cart && session.cart.items) {
        session.cart.items.forEach(item => {
            subtotal += item.unit_price * item.quantity;
        });
    }
    const deliveryFee = session.current_restaurant?.delivery_fee ?? 35.0;
    
    if (!session.cart) session.cart = { items: [] };
    session.cart.subtotal = subtotal;
    session.cart.delivery_fee = deliveryFee;
    session.cart.total = subtotal + deliveryFee;
}

// 🛠️ Función Helper: Construye el ticket visualmente con Modificadores
function buildTicketString(session) {
    calculateTotals(session);
    let ticket = `Aquí tienes el resumen de tu orden:\n\n`;
    
    session.cart.items.forEach(item => {
        ticket += `▪️ ${item.quantity}x ${item.name} - $${(item.unit_price * item.quantity).toFixed(2)}\n`;
        if (item.selected_modifiers && item.selected_modifiers.length > 0) {
            const mods = item.selected_modifiers.map(m => m.name).join(', ');
            ticket += `   ↳ _${mods}_\n`;
        }
    });
    
    if (session.cart.notes && session.cart.notes !== "Sin notas especiales") {
        ticket += `\n📝 *Nota a cocina:* ${session.cart.notes}\n`;
    }
    
    ticket += `\n*Subtotal:* $${session.cart.subtotal.toFixed(2)}\n*Envío:* $${session.cart.delivery_fee.toFixed(2)}\n─────────────────\n*Total:* *$${session.cart.total.toFixed(2)}*\n`;
    
    return ticket;
}

// 🛠️ Función Helper: Envía la pregunta del modificador
async function sendModifierPrompt(pItem, msg) {
    const group = pItem.pending_groups[pItem.current_group_index];
    let prompt = `🍔 *${pItem.name}*`;
    if (pItem.total_qty > 1) prompt += ` (${pItem.item_index} de ${pItem.total_qty})`;
    
    let selectionText = group.selection_type === 'single' ? 'elige 1' : `elige de ${group.min_selections} a ${group.max_selections}`;
    prompt += `\n\n👉 *${group.name}* (${selectionText}):\n`;

    group.options.forEach((opt, idx) => {
        prompt += `${idx + 1}️⃣ ${opt.name}`;
        if (opt.price_delta > 0) prompt += ` (+$${opt.price_delta.toFixed(2)})`;
        prompt += `\n`;
    });

    if (!group.is_required) {
        prompt += `0️⃣ Sin extra / saltar\n`;
    }

    prompt += `\n_Responde con el número de tu elección (ej. "1" o "1, 2")._`;
    return msg.reply(prompt);
}

// 🚀 FUNCIÓN GEOFENCING
async function processNewAddressWithGeofencing(text, user, session, supabase, msg) {
    msg.reply("🤖 Validando cobertura en el mapa para tu nueva dirección... 📍");
    try {
        const geocodeAddress = text.replace(/\boasis\b/gi, 'O.');
        const geoRes = await axios.post(`${process.env.SUPABASE_URL}/functions/v1/google-maps-proxy`,
            { action: "geocode", address: geocodeAddress }, { headers: { Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}` } }
        );
        const geo = geoRes.data;
        const { data: zoneName } = await supabase.rpc('check_location_coverage', { p_lat: geo.lat || 0, p_lon: geo.lon || 0 });

        if (!zoneName) return "🤖 ¡Híjole patrón! Me marca el mapa que esa nueva dirección está **fuera de nuestra zona de cobertura** actual. 😔\n\nPor ahora solo repartimos en nuestras zonas designadas.\n\n¿Tendrás otra dirección de entrega que sí esté en cobertura o mandamos a la anterior?";

        const finalAddress = (geo.formatted_address && geo.formatted_address !== "México") ? `${text} (${geo.formatted_address})` : text;
        await supabase.from('client_profiles').update({ address: finalAddress }).eq('user_id', user.id);
        
        session.current_address = finalAddress;
        session.step = 'ASKING_PAYMENT_METHOD';
        return `🤖 ¡Súper! Estás dentro de la zona de cobertura (*${zoneName}*).\nDirección actualizada a *${finalAddress}*.\n\n${buildTicketString(session)}\n\nPara el pago (solo aceptamos **efectivo** 💵), ¿vas a pagar con cambio exacto o con qué billete?\n_(Nos ayuda muchísimo si tienes el cambio exacto 🙏)_`;
    } catch (e) {
        console.error("Error en Geofencing Dona:", e);
        return "🤖 Uf, falló mi radar del mapa. ¿Me puedes repetir la calle y el número por favor?";
    }
}

// 🏁 FUNCIÓN: CREAR ORDEN CON EL NUEVO WRAPPER (Soporte Modifiers)
async function executeOrderBlueprint(msg, session, user, supabase) {
    if (!user || !user.id) {
        session.step = 'REG_NAME'; 
        return "🤖 *Doña:* ¡Anotado! Pero veo que aún no estás registrado.\n\nPara poder enviarte tu pedido, ¿cuál es tu **nombre y apellido**?";
    }

    try {
        const { data: hasCouriers } = await supabase.rpc('has_active_couriers');
        if (hasCouriers === false) { 
            if (session.reminderTimer) clearTimeout(session.reminderTimer);
            if (session.cancelTimer) clearTimeout(session.cancelTimer);
            session.step = 'IDLE'; session.jimbot_state = 'IDLE'; session.agent = 'JIMBOT'; session.cart = null;
            return "🤖 *Doña:* ¡Híjole patrón! Ahorita todos mis repartidores están ocupados o fuera de turno. No te puedo tomar el pedido en este momento, discúlpame.";
        }

        calculateTotals(session);
        const totalAmount = session.cart.total;
        let cashAmount = session.cart.cash_amount || totalAmount;

        let addressToUse = session.current_address;
        if (!addressToUse) {
            const { data: profile } = await supabase.from('client_profiles').select('address').eq('user_id', user.id).maybeSingle();
            addressToUse = profile?.address || 'Dirección de entrega no especificada';
        }

        const finalOrderNotes = session.cart.notes !== "Sin notas especiales" 
            ? `Vía WhatsApp | Notas del cliente: ${session.cart.notes}` 
            : "Pedido vía WhatsApp (IA)";

        const itemsArray = session.cart.items.map(item => ({
            product_id: item.product_id,
            quantity: item.quantity,
            price: item.unit_price,
            notes: "",
            modifiers: item.selected_modifiers || []
        }));

        const rpcPayload = {
            p_user_id: user.id,
            p_restaurant_id: session.current_restaurant.id,
            p_delivery_address: addressToUse,
            p_delivery_lat: null,
            p_delivery_lon: null,
            p_payment_method: 'cash',
            p_order_notes: finalOrderNotes,
            p_cash_amount: cashAmount,
            p_items: itemsArray,
            p_conversation_id: null
        };

        const { data: orderRes, error: orderErr } = await supabase.rpc('wa_create_order', rpcPayload);

        if (orderErr || !orderRes || !orderRes.success) {
            throw new Error(`Error en wa_create_order: ${JSON.stringify(orderErr || orderRes)}`);
        }

        await new Promise(resolve => setTimeout(resolve, 1000));

        const { data: orderDetails } = await supabase.from('orders').select('confirm_code').eq('id', orderRes.order_id).single();
        const confirmCode = orderDetails?.confirm_code;

        if (session.reminderTimer) clearTimeout(session.reminderTimer);
        if (session.cancelTimer) clearTimeout(session.cancelTimer);
        session.step = 'IDLE'; session.jimbot_state = 'IDLE'; session.agent = 'JIMBOT'; session.cart = null;

        let finalMsg = `🤖 *Doña:* ¡Listo! Tu orden ha sido registrada y enviada a la cocina. 🍳🛵\n\n`;
        finalMsg += `💵 El total a pagar al repartidor es: *$${totalAmount.toFixed(2)}* (ya incluye envío).\n`;
        
        if (cashAmount > totalAmount) {
            finalMsg += `Cambio a devolverte: *$${(cashAmount - totalAmount).toFixed(2)}*\n\n`;
        } else {
            finalMsg += `(Pago exacto, ¡muchas gracias! 🙏)\n\n`;
        }
        
        if (confirmCode) {
            finalMsg += `🔑 *CÓDIGO DE ENTREGA:* ${confirmCode}\n_(Recuerda darle este código a tu repartidor para recibir tu comida)_\n\n`;
        } else if (orderRes.pickup_code) {
            finalMsg += `🔑 *CÓDIGO DE ENTREGA:* ${orderRes.pickup_code}\n_(Recuerda darle este código a tu repartidor para recibir tu comida)_\n\n`;
        }
        
        finalMsg += `📱 *Sigue tu pedido en vivo:* Puedes ver el estatus de tu orden desde nuestra app:\n🔗 https://donna-app-three.vercel.app/\n\n`;
        finalMsg += `🛵 *Tip:* Si tu repartidor hace un excelente trabajo, ¡una propina ayuda muchísimo a dignificar su esfuerzo!\n\n`;
        finalMsg += `¡Buen provecho!`;

        return finalMsg;

    } catch (e) {
        console.error("[🤖 DOÑA CRÍTICO]", e);
        if (session.reminderTimer) clearTimeout(session.reminderTimer);
        if (session.cancelTimer) clearTimeout(session.cancelTimer);
        session.step = 'IDLE'; session.jimbot_state = 'IDLE'; session.agent = 'JIMBOT'; session.cart = null;
        return "🤖 *Doña:* Ay, se me trabó el sistema de la cocina y no pude guardar tu orden por completo. ¿Me das un segundo e intentamos de nuevo?";
    }
}

module.exports = {
    handle: async (msg, session, user, supabase, openai) => {
        const text = msg.body.trim();
        const lowText = text.toLowerCase();
        const userName = user && user.name ? user.name.split(' ')[0] : 'patrón';

        if (!session.cart) session.cart = { items: [] };
        if (!session.pending_queue) session.pending_queue = [];

        if (session.reminderTimer) clearTimeout(session.reminderTimer);
        if (session.cancelTimer) clearTimeout(session.cancelTimer);

        const originalReply = msg.reply.bind(msg);
        msg.reply = async (content, ...args) => {
            const result = await originalReply(content, ...args);
            const activeSteps = ['SELECTING_RESTAURANT', 'ORDERING', 'COLLECTING_MODIFIERS', 'ASKING_NOTES', 'CONFIRMING_ADDRESS', 'WAITING_NEW_ADDRESS', 'ASKING_PAYMENT_METHOD', 'CONFIRMING_ORDER'];
            
            if (activeSteps.includes(session.step)) {
                if (session.reminderTimer) clearTimeout(session.reminderTimer);
                if (session.cancelTimer) clearTimeout(session.cancelTimer);

                const THREE_MINUTES = 3 * 60 * 1000;
                session.reminderTimer = setTimeout(() => {
                    originalReply(`🤖 *Doña:* ¡Oye ${userName}! Se me quedó tu orden a medias. 😅\n\n¿Seguimos con el pedido o te ayudo con otra cosa?`);
                    session.cancelTimer = setTimeout(() => {
                        session.step = 'IDLE'; session.cart = null; session.current_restaurant = null; session.pending_queue = [];
                        session.jimbot_state = 'IDLE'; session.agent = 'JIMBOT';
                        originalReply(`🤖 *Doña:* Como me quedé esperando, cancelé el pedido pendiente para atender a otros clientes. ¡Escríbeme cuando vuelva el hambre, ${userName}! 🌮🛵`);
                    }, THREE_MINUTES);
                }, THREE_MINUTES);
            }
            return result;
        };

        const cancelWords = ['cancela', 'cancelar', 'olvidalo', 'ya no', 'abortar'];
        if (cancelWords.some(w => lowText === w || lowText.startsWith(`${w} `))) {
            if (session.reminderTimer) clearTimeout(session.reminderTimer);
            if (session.cancelTimer) clearTimeout(session.cancelTimer);
            session.step = 'IDLE'; session.cart = null; session.current_restaurant = null; session.pending_queue = [];
            return msg.reply(`🤖 *Doña:* Va que va, orden cancelada, ${userName}. ¿Qué se te antoja hacer entonces?`);
        }
        
        // =========================================================================
        // 🛑 FAST PATH: RECOLECCIÓN DE MODIFICADORES (SIN LLM)
        // =========================================================================
        if (session.step === 'COLLECTING_MODIFIERS') {
            const pItem = session.pending_item;
            if (!pItem) {
                session.step = 'ORDERING';
                return msg.reply("🤖 Se me cruzaron los cables con las opciones. ¿Qué te preparo?");
            }

            const group = pItem.pending_groups[pItem.current_group_index];
            const selectedIndexes = text.match(/\d+/g);

            if (!selectedIndexes) return msg.reply(`🤖 Por favor, responde con el número de tu elección.`);

            if (selectedIndexes.includes('0') && !group.is_required) {
                pItem.current_group_index++;
            } else {
                let chosenMods = [];
                for (let idxStr of selectedIndexes) {
                    const idx = parseInt(idxStr) - 1;
                    if (group.options[idx]) chosenMods.push(group.options[idx]);
                }

                if (chosenMods.length < group.min_selections) return msg.reply(`🤖 Debes elegir al menos ${group.min_selections} opción(es). Intenta de nuevo.`);
                if (group.max_selections > 0 && chosenMods.length > group.max_selections) return msg.reply(`🤖 Máximo ${group.max_selections} opción(es). Intenta de nuevo.`);

                chosenMods.forEach(m => {
                    pItem.selected_modifiers.push({ modifier_id: m.id, group_id: group.id, name: m.name, group_name: group.name, price_delta: m.price_delta });
                    pItem.unit_price += m.price_delta;
                });
                pItem.current_group_index++;
            }

            if (pItem.current_group_index >= pItem.pending_groups.length) {
                session.cart.items.push({
                    product_id: pItem.product_id, name: pItem.name,
                    quantity: pItem.quantity, unit_price: pItem.unit_price,
                    selected_modifiers: pItem.selected_modifiers
                });

                if (session.pending_queue.length > 0) {
                    session.pending_item = session.pending_queue.shift();
                    return sendModifierPrompt(session.pending_item, msg);
                } else {
                    session.step = 'ORDERING';
                    session.pending_item = null;
                    calculateTotals(session);
                    
                    let replyMsg = `🤖 ¡Listo! Agregado al carrito.\n\n🛒 *Tu carrito actual:*\n`;
                    session.cart.items.forEach(item => {
                        replyMsg += `▪️ ${item.quantity}x ${item.name}`;
                        if (item.selected_modifiers && item.selected_modifiers.length > 0) {
                            const mods = item.selected_modifiers.map(m => m.name).join(', ');
                            replyMsg += `\n   ↳ _${mods}_`;
                        }
                        replyMsg += ` - $${(item.unit_price * item.quantity).toFixed(2)}\n`;
                    });
                    replyMsg += `\n*Subtotal:* $${session.cart.subtotal.toFixed(2)}\n\n¿Es todo lo que gustas ordenar, o quieres agregar/quitar algo más?`;
                    return msg.reply(replyMsg);
                }
            } else {
                return sendModifierPrompt(session.pending_item, msg);
            }
        }
        // =========================================================================

        if (session.step === 'SELECTING_RESTAURANT') {
            const isNum = /^\d+$/.test(text); 
            if (isNum && session.restaurants) {
                const idx = parseInt(text) - 1;
                if (session.restaurants[idx]) {
                    const rest = session.restaurants[idx];
                    const { data: menu } = await supabase.from('products').select('*').eq('restaurant_id', rest.id).eq('is_available', true);
                    if (!menu || menu.length === 0) return msg.reply(`🤖 *Doña:* Fíjate que *${rest.name}* no ha subido sus platillos. ¿Checamos otro local?`);

                    // 🛠️ CORRECCIÓN: Leemos el precio directamente de la DB, sin inflarlo un 15%
                    session.menu = menu.map(item => ({ ...item, client_price: Number(item.price.toFixed(2)) }));
                    session.current_restaurant = rest; 
                    session.step = 'ORDERING';
                    session.cart = { items: [] }; 

                    let menuText = `🍔 *Menú de ${rest.name}:*\n\n`;
                    session.menu.forEach((item) => menuText += `🥘 *${item.name}* - $${item.client_price.toFixed(2)}\n_${item.description || ''}_\n\n`);
                    menuText += `¿Qué te preparo? Escribe tu pedido.`;
                    return msg.reply(menuText);
                }
            }
        }

        // --- PREPARAMOS EL CONTEXTO PARA LA MÁQUINA DE ESTADOS DEL LLM ---
        calculateTotals(session);
        let restContext = session.restaurants ? `\nRESTAURANTES EN MEMORIA:\n${session.restaurants.map((r, i) => `${i+1}. ${r.name}`).join('\n')}` : "";
        // Incluir product_id en el contexto para que GPT lo devuelva directamente (sin string-matching)
        let menuContext = session.menu
            ? `\nMENU DEL LOCAL ACTUAL (${session.current_restaurant?.name}):\n` +
              session.menu.map(i => `[ID:${i.id}] ${i.name} - $${i.client_price.toFixed(2)}`).join('\n')
            : "";
        let cartContext = (session.cart && session.cart.items && session.cart.items.length > 0) ? session.cart.items.map(i => `${i.quantity}x ${i.name}`).join(', ') : "Vacío";

        const prompt = `Eres Doña, la agente IA principal de delivery. Usuario: ${userName}.
ESTADO DE LA SESIÓN:
- Etapa Interna: ${session.step}
- Restaurante actual: ${session.current_restaurant ? session.current_restaurant.name : 'Ninguno'}
- Carrito Actual: ${cartContext}
- Total a pagar: $${(session.cart?.total || 0).toFixed(2)}
- Dirección guardada: ${session.current_address || 'Ninguna'}
${restContext}
${menuContext}

MENSAJE DEL USUARIO: "${text}"

INSTRUCCIONES DE RAZONAMIENTO COGNITIVO ESTRICTO SEGÚN LA ETAPA:
Dependiendo de la "Etapa Interna", debes clasificar la intención del usuario.

SI ETAPA ES "ORDERING" o "IDLE":
1. Si pide restaurantes -> action: SHOW_RESTAURANTS.
2. Si selecciona un restaurante -> action: SELECT_RESTAURANT, "restaurant_name": "nombre".
3. Si pide alimento genérico sin local -> action: SEARCH_PRODUCT, "food_query": "comida".
4. Si PIDE PLATILLOS -> action: PROCESS_ORDER, llena "order_data". CRÍTICO: para cada platillo pedido, identifica el producto correcto del menú usando semántica (ej. "chela"→cerveza, "boneles"→Boneless, "sodas"→Sodas, "una coke"→refresco). Devuelve su "product_id" EXACTO del menú (el que aparece en [ID:...]) y el "name" tal como está en el menú. Si el usuario pide algo que definitivamente NO existe en el menú, ponlo en "unknown_items". NO inventes product_ids.
5. Si YA TERMINÓ DE ORDENAR (ej. "es todo", "ya", "listo") -> action: CONFIRM_CART.

SI ETAPA ES "ASKING_NOTES":
6. Evalúa si el usuario da instrucciones para la cocina (ej. "sin cebolla") o si no quiere nada (ej. "no", "correcto"). -> action: SAVE_NOTES, "extracted_info": "las notas textuales o 'Sin notas especiales'".

SI ETAPA ES "CONFIRMING_ADDRESS" o "WAITING_NEW_ADDRESS":
7. Si CONFIRMA que la dirección es correcta (ej. "sí", "correcto", "está bien") -> action: CONFIRM_ADDRESS.
8. Si dice que NO es correcta pero no da una nueva -> action: ASK_NEW_ADDRESS.
9. Si DA UNA NUEVA DIRECCIÓN -> action: UPDATE_ADDRESS, "extracted_info": "nueva dirección completa".

SI ETAPA ES "ASKING_PAYMENT_METHOD":
10. Evalúa el billete. Si dice "500", "con 200", extrae el número. Si dice "exacto", "cambio exacto", extrae el Total a pagar. -> action: SET_PAYMENT, "cash_amount": número. IMPORTANTE: confirmar el monto de pago es suficiente para colocar la orden, no pidas confirmación adicional.

REGLAS GLOBALES:
- Si quiere cancelar todo -> action: CANCEL.
- Si no aplica ninguna de las anteriores -> action: CHAT.

ESTRUCTURA JSON ESTRICTA DE SALIDA:
{
    "thought": "Razonamiento lógico",
    "action": "SHOW_RESTAURANTS | SELECT_RESTAURANT | SHOW_MENU | PROCESS_ORDER | CONFIRM_CART | SAVE_NOTES | CONFIRM_ADDRESS | ASK_NEW_ADDRESS | UPDATE_ADDRESS | SET_PAYMENT | SUBMIT_ORDER | CANCEL | SEARCH_PRODUCT | CHAT",
    "restaurant_name": "Nombre o null",
    "food_query": "Palabra clave o null",
    "extracted_info": "texto extraído (notas o dirección) o null",
    "cash_amount": 500 o null,
    "order_data": {
        "items": [{"product_id": "uuid-exacto-del-menu", "name": "nombre exacto del menú", "quantity": 1}],
        "unknown_items": ["producto que no existe en el menú"]
    },
    "reply": "Respuesta directa"
}`;

        let agentDecision;
        try {
            const gptResponse = await openai.chat.completions.create({
                model: "gpt-4o-mini", messages: [{ role: "system", content: prompt }], response_format: { type: "json_object" }
            });
            agentDecision = JSON.parse(gptResponse.choices[0].message.content);
            console.log(`\n🧠 [DOÑA THOUGHT] ${agentDecision.thought}`);
            console.log(`🎯 [DOÑA ACTION] ${agentDecision.action}\n`);
        } catch (error) {
            console.error("[🤖 DOÑA LLM ERR]", error);
            return msg.reply(`🤖 *Doña:* Uf, se me cruzaron los cables un segundo, ${userName}. ¿Me lo repites porfa?`);
        }

        if (user && user.id && ['SHOW_RESTAURANTS', 'SEARCH_PRODUCT', 'SELECT_RESTAURANT'].includes(agentDecision.action)) {
            const { data: debt } = await supabase.rpc('get_client_total_debt', { p_client_id: user.id });
            if (debt && debt > 0) {
                session.step = 'IDLE'; session.cart = null; session.current_restaurant = null;
                return msg.reply(`🤖 *Doña:* ¡Híjole, ${userName}! 🛑\n\nTienes un adeudo de *$${debt.toFixed(2)}* por una orden anterior. Entra a la app para saldar tu cuenta:\n🔗 https://donna-app-three.vercel.app/`);
            }
        }

        // =========================================================================
        // 🧠 EJECUCIÓN DINÁMICA DE LA MÁQUINA DE ESTADOS (NLP)
        // =========================================================================
        switch (agentDecision.action) {
            case 'SHOW_RESTAURANTS': {
                const { data: res } = await supabase.from('restaurants').select('*').eq('status', 'approved').eq('online', true).order('created_at', { ascending: true });
                if (!res || res.length === 0) return msg.reply(`🤖 *Doña:* Ahorita no hay locales abiertos, ${userName}. Échale un ojo más al rato.`);
                session.restaurants = res; session.step = 'SELECTING_RESTAURANT';
                let list = `🤖 *Doña:* ¿Hambre, ${userName}? Checa los locales abiertos:\n\n`;
                res.forEach((r, i) => list += `${i+1}. *${r.name}* ${r.cuisine_type ? `(${r.cuisine_type})` : ''}\n`);
                return msg.reply(list + `\n👉 *Escribe el número o nombre del restaurante*.`);
            }
            case 'SEARCH_PRODUCT': {
                const query = agentDecision.food_query;
                if (!query) return msg.reply(`🤖 *Doña:* No capté bien, ¿qué se te antojaba?`);
                const { data: onlineRests } = await supabase.from('restaurants').select('id, name').eq('status', 'approved').eq('online', true);
                if (!onlineRests || onlineRests.length === 0) return msg.reply(`🤖 *Doña:* Ahorita no hay locales abiertos, patrón.`);
                const { data: matchedProducts } = await supabase.from('products').select('restaurant_id, name, price').in('restaurant_id', onlineRests.map(r=>r.id)).ilike('name', `%${query}%`).eq('is_available', true);
                if (!matchedProducts || matchedProducts.length === 0) return msg.reply(`🤖 *Doña:* Busqué "${query}" pero ningún local lo tiene ahorita.`);
                const matchedRests = onlineRests.filter(r => [...new Set(matchedProducts.map(p => p.restaurant_id))].includes(r.id));
                session.restaurants = matchedRests; session.step = 'SELECTING_RESTAURANT';
                let list = `🤖 *Doña:* ¡Te encontré opciones de "${query}" en estos locales!\n\n`;
                matchedRests.forEach((r, i) => list += `${i+1}. *${r.name}*\n`);
                return msg.reply(list + `\n👉 *Escribe el número o nombre del restaurante*.`);
            }
            case 'SELECT_RESTAURANT': {
                let targetName = agentDecision.restaurant_name;
                const { data: rest } = await supabase.from('restaurants').select('id, name, commission_bps, delivery_fee').ilike('name', `%${targetName}%`).single();
                if (rest) {
                    const { data: menu } = await supabase.from('products').select('*').eq('restaurant_id', rest.id).eq('is_available', true);
                    if (!menu || menu.length === 0) return msg.reply(`🤖 *Doña:* Fíjate que *${rest.name}* no ha subido sus platillos todavía.`);
                    
                    // 🛠️ CORRECCIÓN: Leemos el precio directamente de la DB, sin inflarlo un 15%
                    session.menu = menu.map(item => ({ ...item, client_price: Number(item.price.toFixed(2)) }));
                    session.current_restaurant = rest; session.step = 'ORDERING'; session.cart = { items: [] };
                    let menuText = `🍔 *Menú de ${rest.name}:*\n\n`;
                    session.menu.forEach((item) => menuText += `🥘 *${item.name}* - $${item.client_price.toFixed(2)}\n_${item.description || ''}_\n\n`);
                    return msg.reply(menuText + `¿Qué te preparo? Escribe tu pedido.`);
                }
                return msg.reply(`🤖 *Doña:* No capté cuál local querías.`);
            }
            case 'SHOW_MENU': {
                if (!session.current_restaurant) return msg.reply(`🤖 *Doña:* Primero escoge un restaurante.`);
                session.step = 'ORDERING';
                let menuText = `🍔 *Menú de ${session.current_restaurant.name}:*\n\n`;
                session.menu.forEach((item) => menuText += `🥘 *${item.name}* - $${item.client_price.toFixed(2)}\n_${item.description || ''}_\n\n`);
                return msg.reply(menuText + `¿Qué te preparo?`);
            }
            
            case 'PROCESS_ORDER': {
                const orderData = agentDecision.order_data;
                if (!orderData || !orderData.items) return msg.reply("🤖 *Doña:* No capté qué platillos querías. ¿Me confirmas?");
                
                const validItems = [];
                const invalidItems = orderData.unknown_items || [];
                session.pending_queue = []; 

                for (const reqItem of orderData.items) {
                    // Buscar por product_id primero (GPT lo resolvió semánticamente)
                    // Si no viene ID o no hace match, caer al fuzzy matcher como red de seguridad
                    const existsInMenu = (reqItem.product_id
                        ? session.menu.find(p => p.id === reqItem.product_id)
                        : null) ?? findProductInMenu(session.menu, reqItem.name);
                    if (existsInMenu) {
                        const { data: prodMods } = await supabase.rpc('get_product_with_modifiers', { p_product_id: existsInMenu.id });
                        if (prodMods && prodMods.modifier_groups && prodMods.modifier_groups.length > 0) {
                            for (let i = 0; i < reqItem.quantity; i++) {
                                session.pending_queue.push({
                                    product_id: existsInMenu.id, name: existsInMenu.name, quantity: 1, base_price: existsInMenu.client_price,
                                    unit_price: existsInMenu.client_price, selected_modifiers: [], pending_groups: prodMods.modifier_groups,
                                    current_group_index: 0, item_index: i + 1, total_qty: reqItem.quantity
                                });
                            }
                        } else {
                            validItems.push({ product_id: existsInMenu.id, name: existsInMenu.name, quantity: reqItem.quantity, unit_price: existsInMenu.client_price, selected_modifiers: [] });
                        }
                    } else {
                        invalidItems.push(reqItem.name);
                    }
                }

                if (validItems.length > 0) session.cart.items.push(...validItems);

                if (session.pending_queue.length > 0) {
                    session.step = 'COLLECTING_MODIFIERS';
                    session.pending_item = session.pending_queue.shift();
                    let initialMsg = "🤖 ¡Anotado!";
                    if (invalidItems.length > 0) initialMsg += `\n⚠️ No manejo: *${invalidItems.join(', ')}*.`;
                    await msg.reply(initialMsg + `\n\nAntes de agregarlo al carrito, personaliza tu pedido:`);
                    return sendModifierPrompt(session.pending_item, msg);
                }

                let replyMsg = `🤖 *Doña:* ¡Anotado!\n\n`;
                if (invalidItems.length > 0) replyMsg += `⚠️ Fíjate que no manejo: *${invalidItems.join(', ')}*.\n\n`;
                if (session.cart.items.length === 0) return msg.reply(`${replyMsg}Tu carrito quedó vacío. ¿Qué te preparo?`);

                calculateTotals(session);
                replyMsg += `🛒 *Tu carrito actual:*\n`;
                session.cart.items.forEach(item => {
                    replyMsg += `▪️ ${item.quantity}x ${item.name}`;
                    if (item.selected_modifiers && item.selected_modifiers.length > 0) replyMsg += `\n   ↳ _${item.selected_modifiers.map(m => m.name).join(', ')}_`;
                    replyMsg += ` - $${(item.unit_price * item.quantity).toFixed(2)}\n`;
                });
                return msg.reply(replyMsg + `\n*Subtotal:* $${session.cart.subtotal.toFixed(2)}\n\n¿Es todo lo que gustas ordenar, o quieres agregar algo más?`);
            }

            case 'CONFIRM_CART': {
                if (!session.cart || !session.cart.items || session.cart.items.length === 0) return msg.reply("🤖 *Doña:* Tu carrito está vacío. ¿Qué te preparo primero?");
                session.step = 'ASKING_NOTES';
                return msg.reply(`🤖 *Doña:* ¡Perfecto, ${userName}!\n\n¿Tienes alguna **instrucción especial** para la cocina (ej. "sin cebolla")? Si no, dime *"no"*.`);
            }

            case 'SAVE_NOTES': {
                session.cart.notes = agentDecision.extracted_info || "Sin notas especiales";
                if (user && user.id) {
                    let { data: profile } = await supabase.from('client_profiles').select('address').eq('user_id', user.id).maybeSingle();
                    session.current_address = profile?.address;
                    if (session.current_address) {
                        session.step = 'CONFIRMING_ADDRESS';
                        return msg.reply(`🤖 *Doña:* ¡Anotado!\n\nTengo esta dirección tuya guardada:\n📍 *${session.current_address}*\n\n¿Es correcta o enviamos a otra parte?`);
                    } else {
                        session.step = 'WAITING_NEW_ADDRESS';
                        return msg.reply(`🤖 *Doña:* ¡Anotado!\n\nOye, no tengo una dirección de entrega guardada tuya. ¿Me escribes tu dirección completa (Calle, número, colonia)?`);
                    }
                } else {
                    session.step = 'ASKING_PAYMENT_METHOD';
                    return msg.reply(`🤖 *Doña:* ¡Perfecto!\n\n${buildTicketString(session)}\n\nPara el pago (solo aceptamos *efectivo* 💵), ¿con qué billete vas a pagar?\n_(Nos ayudas muchísimo si tu pago es exacto 🙏)_`);
                }
            }

            case 'CONFIRM_ADDRESS': {
                session.step = 'ASKING_PAYMENT_METHOD';
                return msg.reply(`🤖 *Doña:* ¡Excelente!\n\n${buildTicketString(session)}\n\nPara el pago (solo aceptamos *efectivo* 💵), ¿con qué billete vas a pagar?\n_(Nos ayudas muchísimo si tu pago es exacto 🙏)_`);
            }

            case 'ASK_NEW_ADDRESS': {
                session.step = 'WAITING_NEW_ADDRESS';
                return msg.reply("🤖 *Doña:* Va, escríbeme la nueva dirección completa para actualizarla:");
            }

            case 'UPDATE_ADDRESS': {
                if (agentDecision.extracted_info && user && user.id) return await processNewAddressWithGeofencing(agentDecision.extracted_info, user, session, supabase, msg);
                return msg.reply(`🤖 *Doña:* No capté la dirección, ¿me la escribes completa de nuevo?`);
            }

            case 'SET_PAYMENT': {
                calculateTotals(session);
                const total = session.cart.total;
                let cashAmount = agentDecision.cash_amount;

                if (!cashAmount) return msg.reply(`🤖 *Doña:* Entendido. El total es de *$${total.toFixed(2)}*. ¿Con qué billete vas a pagar?`);
                if (cashAmount < total) return msg.reply(`🤖 *Doña:* Híjole, el total es de *$${total.toFixed(2)}* y con $${cashAmount} no alcanza. ¿Con cuánto vas a pagar?`);

                session.cart.payment_method = 'cash';
                session.cart.cash_amount = cashAmount;
                // La confirmación del monto ES la confirmación del pedido — colocar directo
                return await executeOrderBlueprint(msg, session, user, supabase);
            }

            case 'SUBMIT_ORDER': {
                // Fallback por si GPT aún genera esta acción
                return await executeOrderBlueprint(msg, session, user, supabase);
            }

            case 'SWITCH_AGENT': {
                session.agent = agentDecision.target_agent; session.step = 'IDLE';
                return msg.reply(`🤖 *Doña:* ¡Órale! Ese tema lo maneja mi compañero. Te paso con él...`);
            }
            case 'CANCEL': {
                if (session.reminderTimer) clearTimeout(session.reminderTimer);
                if (session.cancelTimer) clearTimeout(session.cancelTimer);
                session.step = 'IDLE'; session.cart = null; session.current_restaurant = null; session.pending_queue = [];
                return msg.reply(agentDecision.reply || `🤖 *Doña:* Listo, cancelado. ¿Qué más hacemos, ${userName}?`);
            }
            case 'CHAT':
            default: return msg.reply(`🤖 *Doña:* ${agentDecision.reply || '¿En qué más te ayudo?'}`);
        }
    }
};