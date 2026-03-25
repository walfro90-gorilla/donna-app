const express = require('express');
const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const { createClient } = require('@supabase/supabase-js');
const OpenAI = require('openai');
const axios = require('axios');
require('dotenv').config();

// Importación de Agentes
const dona = require('./core/agents/dona');
const ketzal = require('./core/agents/ketzal');
const gorilla = require('./core/agents/gorilla');

// --- 🌐 LEVANTAR SERVIDOR EXPRESS (API REST PARA CRM Y NOTIFICACIONES PUSH) ---
const app = express();
app.use(express.json({ limit: '50mb' })); // Límite alto para permitir envío de imágenes/PDFs en Base64 desde el CRM

// 1. Endpoint Original: Para recibir mensajes manuales desde el CRM (Next.js)
app.post('/send', async (req, res) => {
    // 🛡️ Seguridad: Verificar que Next.js tenga permiso para disparar mensajes
    if (req.headers['x-bot-secret'] !== process.env.DONNA_BOT_SECRET) {
        return res.status(401).json({ error: 'Unauthorized' });
    }

    try {
        const { to, message, mediaBase64, mimetype, filename } = req.body;
        
        // Asegurar que el número termine en @c.us
        const chatId = to.includes('@') ? to : `${to}@c.us`;

        if (mediaBase64) {
            const media = new MessageMedia(mimetype, mediaBase64, filename);
            await client.sendMessage(chatId, media, { caption: message });
        } else {
            await client.sendMessage(chatId, message);
        }
        res.json({ success: true });
    } catch (error) {
        console.error("🔥 Error en endpoint /send:", error);
        res.status(500).json({ error: error.message });
    }
});

// 2. NUEVO Endpoint: Para recibir Notificaciones Push de estatus desde Supabase/Flutter
app.post('/notify', async (req, res) => {
    // Soportamos el header de Claude o el nuestro estándar
    const receivedSecret = req.headers['x-clawbot-secret'] || req.headers['x-bot-secret'];
    
    if (receivedSecret !== process.env.DONNA_BOT_SECRET) {
        return res.status(401).json({ error: 'Unauthorized' });
    }

    const { phone, message } = req.body;

    if (!phone || !message) {
        return res.status(400).json({ error: 'phone y message son requeridos' });
    }

    try {
        // Limpiamos el número: quitamos el '+' y cualquier caracter raro, agregamos @c.us
        const cleanPhone = phone.replace(/\D/g, '');
        const chatId = `${cleanPhone}@c.us`;
        
        await client.sendMessage(chatId, message);
        console.log(`\n✅ [NOTIFY] Push Notification de estatus enviada a ${cleanPhone}\n`);
        
        return res.json({ success: true, phone: cleanPhone });
    } catch (err) {
        console.error('❌ [NOTIFY] Error enviando push:', err.message);
        return res.status(500).json({ error: err.message });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`\n🚀 Servidor Express (CRM & Notify) corriendo en puerto ${PORT}\n`));

// --- 🤖 INICIALIZACIÓN DE WHATSAPP Y CLIENTES ---
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const client = new Client({
    authStrategy: new LocalAuth(),
    puppeteer: { args: ['--no-sandbox', '--disable-setuid-sandbox'], handleSIGINT: false }
});

const sessions = {}; 

client.on('qr', qr => qrcode.generate(qr, {small: true}));
client.on('ready', () => console.log('✅ DOÑA REPARTOS: Mothership v18.0 (CRM + Notify Integrados) Online.'));

// =========================================================================
// 🕐 DEBOUNCER — Agrupa mensajes rápidos antes de procesar (evita spam)
// =========================================================================
const DEBOUNCE_MS = 3000;
const messageBuffers = {};
const debounceTimers = {};

async function showTyping(msg, durationMs = 1200) {
    try {
        const chat = await msg.getChat();
        await chat.sendStateTyping();
        await new Promise(r => setTimeout(r, durationMs));
        await chat.clearState();
    } catch(e) { /* ignorar si falla */ }
}

client.on('message_create', async msg => {
    if (msg.fromMe || msg.isStatus || msg.broadcast || msg.from.includes('@g.us')) return;
    const from = msg.from;
    if (!messageBuffers[from]) messageBuffers[from] = [];
    messageBuffers[from].push(msg.body.trim());
    if (debounceTimers[from]) clearTimeout(debounceTimers[from]);
    debounceTimers[from] = setTimeout(async () => {
        const texts = messageBuffers[from] || [];
        messageBuffers[from] = [];
        delete debounceTimers[from];
        msg.body = texts.join('\n');
        await processMessage(msg);
    }, DEBOUNCE_MS);
});

async function processMessage(msg) {
    const from = msg.from;
    let rawNumber = from.replace('@c.us', '').replace('@s.whatsapp.net', '');
    let contactName = null;

    try {
        const contact = await msg.getContact();
        if (contact) {
            if (contact.number) rawNumber = contact.number;
            contactName = contact.pushname || contact.name || null;
        }
    } catch (e) {
        console.log("[WARNING] Bypass Contacto falló, usando rawNumber.");
    }
    const last10Digits = rawNumber.slice(-10);

    // =========================================================================
    // 📤 OUTBOX INTERCEPTOR: ENVÍA WEBHOOK A NEXT.JS AL RESPONDER
    // =========================================================================
    const originalReply = msg.reply.bind(msg);
    msg.reply = async (content, ...args) => {
        console.log(`\n[📤 OUTBOX] -> ${rawNumber}:\n"${content}"`);
        if (!content || content.trim() === '') return;

        // 📡 Disparar evento bot_message a Vercel (Next.js CRM)
        if (process.env.DONNA_WEBHOOK_URL) {
            try {
                const webhookPayload = {
                    event: 'bot_message',
                    from: from, 
                    body: content,
                    timestamp: Math.floor(Date.now() / 1000)
                };

                // Enviamos de forma asíncrona sin bloquear el envío real a WA
                axios.post(process.env.DONNA_WEBHOOK_URL, webhookPayload, {
                    headers: { 
                        'Content-Type': 'application/json',
                        'x-webhook-secret': process.env.DONNA_WEBHOOK_SECRET 
                    },
                    timeout: 5000
                }).catch(err => {
                    console.error('⚠️ [CRM OUTBOX] Falló envío a Vercel:', err.message);
                });
            } catch (err) {
                console.error("Error armando webhook de salida:", err);
            }
        }

        return originalReply(content, ...args);
    };
    // =========================================================================

    let text = msg.body.trim();

    // Iniciar sesión si no existe
    if (!sessions[from]) {
        sessions[from] = { agent: 'JIMBOT', step: 'IDLE', jimbot_state: 'IDLE', lang: 'es' };
        console.log(`\n[🆕 NUEVA SESIÓN] Número: ${rawNumber}`);
    }

    console.log(`\n[📥 INBOX] De: ${rawNumber} | Msg Original: "${text}"`);

    // Consultamos al usuario en la BD
    let { data: user } = await supabase.from('users').select('*').filter('phone', 'like', `%${last10Digits}`).maybeSingle();
    const userName = user && user.name ? user.name.split(' ')[0] : (contactName || 'Usuario nuevo');

    // =========================================================================
    // 📡 WEBHOOK DISPATCH PARA NEXT.JS (INBOX) Y KILL-SWITCH
    // =========================================================================
    let autoRespond = true; 

    if (process.env.DONNA_WEBHOOK_URL) {
        try {
            let mediaData = null;
            if (msg.hasMedia) {
                try {
                    const media = await msg.downloadMedia();
                    if (media) {
                        mediaData = { 
                            data: media.data, 
                            mimetype: media.mimetype, 
                            filename: media.filename || null 
                        };
                    }
                } catch (err) { 
                    console.error('Error descargando media para webhook:', err.message); 
                }
            }

            const webhookPayload = {
                event: 'message',
                messageId: msg.id._serialized,
                from: msg.from, 
                body: msg.body || '',
                type: msg.type, 
                timestamp: msg.timestamp,
                hasMedia: msg.hasMedia,
                media: mediaData,
                contactName: contactName
            };

            const response = await axios.post(process.env.DONNA_WEBHOOK_URL, webhookPayload, {
                headers: { 
                    'Content-Type': 'application/json',
                    'x-webhook-secret': process.env.DONNA_WEBHOOK_SECRET 
                },
                timeout: 8000 
            });

            // Si el CRM nos responde que hay un humano atendiendo, pausamos el bot
            if (response.data && typeof response.data.autoRespond !== 'undefined') {
                autoRespond = response.data.autoRespond;
            }
        } catch (err) {
            console.error('\n⚠️ [CRM WEBHOOK INBOX] Falló la conexión con Vercel/Next.js:');
            if (err.response) {
                console.error(`   ❌ Status Code: ${err.response.status}`);
                console.error(`   ❌ Respuesta exacta de Next.js:`, JSON.stringify(err.response.data, null, 2));
            } else if (err.request) {
                console.error(`   📡 Sin respuesta del servidor.`);
            } else {
                console.error(`   ⚙️ Error interno de Axios:`, err.message);
            }
        }
    }

    // 🛑 KILL-SWITCH: SI UN ASESOR TOMÓ EL CONTROL EN EL CRM, LA IA SE QUEDA CALLADA
    if (!autoRespond) {
        console.log(`[CRM] 🤫 Bot pausado para ${rawNumber} — Intervención humana activa.`);
        return; 
    }
    // =========================================================================

    // --- LÓGICA DE AGENTES E INTELIGENCIA ARTIFICIAL ---
    try {
        if (sessions[from].agent === 'JIMBOT' && sessions[from].step === 'IDLE') {
            const routingPrompt = `Eres el Enrutador Cognitivo de Doña Repartos. Usuario: ${userName}.
            Analiza el mensaje: "${text}".
            Asigna el agente según la intención primaria:
            1. Si SOLO saluda o charla: agent="JIMBOT", action="CHAT". Salúdalo de forma amigable y breve.
            2. Si tiene hambre, quiere pedir comida, menú, o MENCIONA UN RESTAURANTE ESPECÍFICO: agent="DOÑA", action="TRIGGER_DONA".
               - Extrae el nombre en "restaurant_name" si menciona un local específico, sino null.
            3. Si quiere REGISTRAR SU RESTAURANTE, afiliar su negocio: agent="GORILLA", action="TRIGGER_GORILLA".
            4. Si quiere trabajar como repartidor: agent="KETZAL", action="TRIGGER_KETZAL".
            5. Si pregunta por UBICACIÓN, DIRECCIÓN o DÓNDE ESTÁN: agent="JIMBOT", action="FAQ_LOCATION".
            6. Si pregunta por HORARIOS o A QUÉ HORA abren/cierran: agent="JIMBOT", action="FAQ_HOURS".
            7. Si pregunta CÓMO FUNCIONA, CÓMO PEDIR o cómo usar el servicio: agent="JIMBOT", action="FAQ_HOW".
            8. Si pregunta por COBERTURA, ZONAS o si llegan a su colonia: agent="JIMBOT", action="FAQ_COVERAGE".
            Responde JSON estricto: {"agent": "DOÑA|JIMBOT|GORILLA|KETZAL", "action": "...", "restaurant_name": "nombre extraído o null", "reply": "tu respuesta amigable (solo si action=CHAT)"}`;

            const routing = await openai.chat.completions.create({ model: "gpt-4o-mini", messages: [{ role: "system", content: routingPrompt }], response_format: { type: "json_object" } });
            const aiDecision = JSON.parse(routing.choices[0].message.content);

            if (aiDecision.agent !== 'JIMBOT') {
                sessions[from].agent = aiDecision.agent;
                sessions[from].jimbot_state = 'IN_AGENT';
                sessions[from].step = 'IDLE';

                if (aiDecision.agent === 'DOÑA') {
                    if (aiDecision.restaurant_name) {
                        sessions[from].step = 'SELECTING_RESTAURANT';
                        msg.body = `SISTEMA: El usuario seleccionó "${aiDecision.restaurant_name}"`;
                        text = msg.body;
                    } else if (aiDecision.action === 'TRIGGER_DONA') {
                        msg.body = "Muestra la lista de restaurantes abiertos";
                        text = msg.body;
                    }
                }
            } else {
                switch (aiDecision.action) {
                    case 'FAQ_LOCATION':
                        await showTyping(msg, 900);
                        return msg.reply('Somos un servicio de delivery a domicilio en Juárez, Chih. No tenemos restaurante físico propio — te llevamos comida de los locales afiliados a donde estés. 🏠');
                    case 'FAQ_HOURS':
                        await showTyping(msg, 900);
                        return msg.reply('Estamos disponibles cuando los restaurantes afiliados están en línea. Escríbeme "restaurantes" para ver quién está abierto ahorita. 🕐');
                    case 'FAQ_HOW':
                        await showTyping(msg, 900);
                        return msg.reply('¡Es muy fácil! Me dices qué se te antoja, te muestro el menú, haces tu pedido y pagas en efectivo al repartidor. Todo por WhatsApp. ¿Le entramos? 🛵');
                    case 'FAQ_COVERAGE':
                        await showTyping(msg, 900);
                        return msg.reply('Repartimos en Juárez, Chih. Dime tu colonia y te confirmo si llegamos. 📍');
                    default:
                        await showTyping(msg, 1000);
                        return msg.reply(aiDecision.reply || '¡Hola! ¿En qué te puedo ayudar? 😊');
                }
            }
        }

        const isRegistering = sessions[from].step.startsWith('REG_');
        if (isRegistering && !user) {
            return await handleRegistration(msg, sessions[from], rawNumber, contactName);
        }

        if (sessions[from].agent !== 'JIMBOT') {
            return await handleAgentDelegation(msg, sessions[from], user);
        }

    } catch (e) { console.error("\n🔥 [CRÍTICO] ERROR MAIN:", e.stack); }
}

async function handleAgentDelegation(msg, session, user) {
    try {
        switch (session.agent) {
            case 'DOÑA': 
                const result = await dona.handle(msg, session, user, supabase, openai);
                if (typeof result === 'string' && result.trim().length > 0) return msg.reply(result);
                break;
            case 'KETZAL': await ketzal.handle(msg, session, user, supabase, openai); break;
            case 'GORILLA': await gorilla.handle(msg, session, user, supabase, openai); break;
        }
    } catch (err) {
        console.error(`🔥 ERROR EN AGENTE ${session.agent}:`, err.stack);
        msg.reply("Tuvimos un parpadeo interno. ¿Me lo repites?");
    }
}

async function handleRegistration(msg, session, rawNumber, contactName) {
    const text = msg.body.trim();
    
    if (session.step === 'IDLE' || session.step === 'ASKED_FOR_MENU') {
        session.step = 'REG_NAME';
        const nombreSugerido = contactName ? ` (¿Es ${contactName}?)` : '';
        return msg.reply(`¡Excelente! Antes de procesar tu orden, necesito registrarte en Doña Repartos.\n\n¿Cuál es tu **nombre y apellido**?${nombreSugerido}`);
    }

    try {
        switch (session.step) {
            case 'REG_NAME':
                session.reg_name = text; session.step = 'REG_EMAIL';
                return msg.reply(`Gracias, ${text}. ¿Cuál es tu **correo electrónico**?\n\n_(Nota: Este correo es solo para que puedas acceder a tu cuenta en la app y recuperar tu contraseña)_`);
            
            case 'REG_EMAIL':
                if (!text.includes('@')) return msg.reply("Correo inválido. Intenta de nuevo con formato estándar (ejemplo@correo.com):");
                session.reg_email = text; session.step = 'REG_ADDRESS';
                return msg.reply("¿A qué dirección enviamos tus pedidos? (Calle, número y colonia):");
            
            case 'REG_ADDRESS':
                msg.reply("Validando cobertura en el mapa... 📍");
                
                const geocodeAddress = text.replace(/\boasis\b/gi, 'O.');
                
                const geoRes = await axios.post(`${process.env.SUPABASE_URL}/functions/v1/google-maps-proxy`, 
                    { action: "geocode", address: geocodeAddress }, { headers: { Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}` } }
                );
                const geo = geoRes.data;

                const { data: zoneName } = await supabase.rpc('check_location_coverage', { p_lat: geo.lat || 0, p_lon: geo.lon || 0 });

                if (!zoneName) {
                    return msg.reply("¡Híjole! Me marca el mapa que esa dirección está **fuera de nuestra zona de cobertura** actual. 😔\n\nPor el momento solo repartimos en nuestras zonas designadas.\n\n¿Tienes alguna otra dirección de entrega que esté dentro de la zona?");
                }

                msg.reply(`¡Súper! Estás dentro de la zona de cobertura (*${zoneName}*). Configurando tu perfil...`);

                const finalAddress = (geo.formatted_address && geo.formatted_address !== "México") ? `${text} (${geo.formatted_address})` : text;
                
                // Generar contraseña temporal segura
                const animals = ['Leon', 'Tigre', 'Panda', 'Zorro', 'Lobo', 'Oso', 'Delfin', 'Aguila', 'Puma', 'Jaguar', 'Halcon', 'Gato', 'Perro', 'Buho'];
                const randomAnimal = animals[Math.floor(Math.random() * animals.length)];
                const randomNum = Math.floor(Math.random() * 900) + 100;
                const tempPassword = `${randomAnimal}${randomNum}!`;

                const { data: auth, error: authErr } = await supabase.auth.admin.createUser({
                    email: session.reg_email, password: tempPassword,
                    email_confirm: true, user_metadata: { role: "client", name: session.reg_name, phone: rawNumber }
                });
                if (authErr) throw authErr;
                
                await supabase.rpc('register_client_v2', {
                    p_user_id: auth.user.id, p_email: session.reg_email, p_name: session.reg_name,
                    p_phone: rawNumber, p_address: finalAddress, p_address_structured: geo, 
                    p_location_lat: geo.lat || 0, p_location_lon: geo.lon || 0, p_location_place_id: geo.place_id || null
                });

                const { data: newUser } = await supabase.from('users').select('*').eq('id', auth.user.id).single();

                const welcomeMsg = `¡Bienvenido, *${session.reg_name}*! Registro exitoso en Doña Repartos. 🎉\n\n🔐 Tu cuenta web ha sido creada. Para revisar el estatus de tus órdenes, accede a la app:\n🔗 https://donna-app-three.vercel.app/\n\n📧 *Usuario:* ${session.reg_email}\n🔑 *Contraseña:* ${tempPassword}`;

                // Si el usuario intentó ordenar antes de registrarse, lo devolvemos directo a su carrito
                if (session.cart && session.agent === 'DOÑA') {
                    await msg.reply(`${welcomeMsg}\n\nProcesando tu orden pendiente... ⏳`);
                    session.step = 'CONFIRMING_ORDER';
                    msg.body = 'si'; 
                    const result = await dona.handle(msg, session, newUser, supabase, openai);
                    if (typeof result === 'string' && result.trim().length > 0) return msg.reply(result);
                } else {
                    session.step = 'IDLE'; 
                    session.jimbot_state = 'IN_AGENT'; 
                    return msg.reply(welcomeMsg);
                }
                break;
        }
    } catch (err) { 
        console.error("🔥 Error en Registration:", err);
        msg.reply("Tuvimos un detalle guardando los datos. ¿Me pasas un correo distinto para intentar de nuevo?");
    }
}

client.initialize();