// Supabase Edge Function: maps-proxy
// Secure proxy for Google Places Autocomplete and Place Details.
// Reads GOOGLE_MAPS_API_KEY from Edge Function secrets.
// CORS enabled for web clients.
// Deno runtime

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const API_KEY = Deno.env.get("GOOGLE_MAPS_API_KEY");

type Json = Record<string, unknown> | Array<unknown> | string | number | boolean | null;

const json = (data: Json, init: ResponseInit = {}) => {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("access-control-allow-origin", "*");
  headers.set("access-control-allow-headers", "authorization, x-client-info, apikey, content-type");
  headers.set("access-control-allow-methods", "GET, POST, OPTIONS");
  headers.set("access-control-max-age", "86400");
  return new Response(JSON.stringify(data), { ...init, headers });
};

const badRequest = (msg: string) => json({ error: msg }, { status: 400 });
const serverError = (msg: string) => json({ error: msg }, { status: 500 });

async function handleAutocomplete(body: any) {
  const input = (body?.input ?? body?.query ?? "").toString();
  if (!input) return badRequest("Missing 'input'");
  const language = (body?.language ?? "es").toString();
  // Relax default: don't force country; allow client to pass components if desired
  const components = (body?.components ?? "").toString();
  const sessiontoken = (body?.sessionToken ?? body?.sessiontoken ?? "").toString();
  const types = (body?.types ?? "").toString(); // e.g., address, geocode, establishment

  const params = new URLSearchParams({ input, language, key: API_KEY ?? "" });
  if (components) params.set("components", components);
  if (sessiontoken) params.set("sessiontoken", sessiontoken);
  if (types) params.set("types", types);

  const url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params.toString()}`;
  const res = await fetch(url);
  if (!res.ok) return serverError(`Upstream error: ${res.status}`);
  const data = await res.json();

  // Surface Google's status and error_message to the client for debugging
  const status = (data?.status ?? "").toString();
  const error_message = (data?.error_message ?? "").toString();

  // Normalize predictions to a compact shape
  const results = (data?.predictions ?? []).map((p: any) => ({
    description: p.description,
    place_id: p.place_id,
    types: p.types,
    structured_formatting: p.structured_formatting,
  }));

  return json({ results, status, error_message });
}

async function handlePlaceDetails(body: any) {
  const placeId = (body?.placeId ?? body?.place_id ?? "").toString();
  if (!placeId) return badRequest("Missing 'placeId'");
  const language = (body?.language ?? "es").toString();

  const fields = [
    "place_id",
    "geometry/location",
    "formatted_address",
    "name",
  ].join(",");

  const params = new URLSearchParams({ place_id: placeId, language, fields, key: API_KEY ?? "" });
  const url = `https://maps.googleapis.com/maps/api/place/details/json?${params.toString()}`;
  const res = await fetch(url);
  if (!res.ok) return serverError(`Upstream error: ${res.status}`);
  const data = await res.json();

  const status = (data?.status ?? "").toString();
  const error_message = (data?.error_message ?? "").toString();

  const r = data?.result ?? {};
  const loc = r?.geometry?.location;
  const lat = typeof loc?.lat === "number" ? loc.lat : undefined;
  const lon = typeof loc?.lng === "number" ? loc.lng : (typeof loc?.lon === "number" ? loc.lon : undefined);

  return json({
    place_id: r?.place_id,
    formatted_address: r?.formatted_address ?? r?.name ?? "",
    lat,
    lon,
    name: r?.name ?? "",
    status,
    error_message,
  });
}

async function handleGeocode(body: any) {
  const address = (body?.address ?? "").toString();
  if (!address) return badRequest("Missing 'address'");
  const language = (body?.language ?? "es").toString();
  const components = (body?.components ?? "").toString(); // relaxed

  const params = new URLSearchParams({ address, language, key: API_KEY ?? "" });
  if (components) params.set("components", components);

  const url = `https://maps.googleapis.com/maps/api/geocode/json?${params.toString()}`;
  const res = await fetch(url);
  if (!res.ok) return serverError(`Upstream error: ${res.status}`);
  const data = await res.json();
  const first = data?.results?.[0];
  const status = (data?.status ?? "").toString();
  const error_message = (data?.error_message ?? "").toString();
  const loc = first?.geometry?.location;
  const lat = typeof loc?.lat === "number" ? loc.lat : undefined;
  const lon = typeof loc?.lng === "number" ? loc.lng : undefined;
  return json({
    formatted_address: first?.formatted_address ?? address,
    place_id: first?.place_id,
    lat,
    lon,
    status,
    error_message,
  });
}

async function handleReverseGeocode(body: any) {
  const lat = body?.lat ?? body?.latitude;
  const lon = body?.lon ?? body?.lng ?? body?.longitude;
  if (typeof lat !== "number" || typeof lon !== "number") {
    return badRequest("Missing 'lat' and 'lon'");
  }
  const language = (body?.language ?? "es").toString();

  const latlng = `${lat},${lon}`;
  const params = new URLSearchParams({ latlng, language, key: API_KEY ?? "" });

  const url = `https://maps.googleapis.com/maps/api/geocode/json?${params.toString()}`;
  const res = await fetch(url);
  if (!res.ok) return serverError(`Upstream error: ${res.status}`);
  const data = await res.json();
  const first = data?.results?.[0];
  const status = (data?.status ?? "").toString();
  const error_message = (data?.error_message ?? "").toString();

  // Extract structured components from address_components
  const addressComponents: any = {};
  if (first?.address_components) {
    for (const c of first.address_components) {
      const types = c.types ?? [];
      if (types.includes("street_number")) addressComponents.street_number = c.long_name;
      if (types.includes("route")) addressComponents.route = c.long_name;
      if (types.includes("locality")) addressComponents.city = c.long_name;
      if (types.includes("administrative_area_level_1")) addressComponents.state = c.long_name;
      if (types.includes("country")) addressComponents.country = c.long_name;
      if (types.includes("postal_code")) addressComponents.postal_code = c.long_name;
      if (types.includes("sublocality")) addressComponents.sublocality = c.long_name;
      if (types.includes("neighborhood")) addressComponents.neighborhood = c.long_name;
    }
  }

  return json({
    formatted_address: first?.formatted_address ?? "",
    place_id: first?.place_id,
    lat,
    lon,
    address_components: addressComponents,
    status,
    error_message,
  });
}

async function handleAddressValidation(body: any) {
  const address = (body?.address ?? "").toString();
  if (!address) return badRequest("Missing 'address'");
  const language = (body?.language ?? "es").toString();

  // Address Validation API endpoint
  const url = "https://addressvalidation.googleapis.com/v1:validateAddress?key=" + (API_KEY ?? "");
  const payload = {
    address: { addressLines: [address] },
    enableUspsCass: false,
    languageOptions: { returnEnglishLatinAddress: language === "en" },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (!res.ok) return serverError(`Upstream error: ${res.status}`);
  const data = await res.json();

  const result = data?.result;
  const verdict = result?.verdict;
  const address_complete = verdict?.addressComplete ?? false;
  const has_unconfirmed = verdict?.hasUnconfirmedComponents ?? false;

  const postal = result?.address?.postalAddress;
  const geocode = result?.geocode;
  const lat = geocode?.location?.latitude;
  const lon = geocode?.location?.longitude;

  return json({
    formatted_address: postal?.addressLines?.join(", ") ?? address,
    address_complete,
    has_unconfirmed,
    lat,
    lon,
    postal_address: postal,
    verdict,
    full_result: result,
  });
}

serve(async (req) => {
  // Preflight
  if (req.method === "OPTIONS") return json({ ok: true });

  try {
    if (!API_KEY) return serverError("GOOGLE_MAPS_API_KEY is not configured in Edge Function secrets");

    const contentType = req.headers.get("content-type") ?? "";
    const isJson = contentType.includes("application/json");
    const body = isJson ? await req.json() : {};

    const action = (body?.action ?? "").toString();

    switch (action) {
      case "autocomplete":
        return await handleAutocomplete(body);
      case "place_details":
      case "place-details":
        return await handlePlaceDetails(body);
      case "geocode":
        return await handleGeocode(body);
      case "reverse_geocode":
      case "reverse-geocode":
        return await handleReverseGeocode(body);
      case "validate_address":
      case "validate-address":
        return await handleAddressValidation(body);
      default:
        return badRequest("Unknown or missing 'action' (expected: autocomplete | place_details | geocode | reverse_geocode | validate_address)");
    }
  } catch (err) {
    console.error("maps-proxy error", err);
    return serverError("Unexpected error");
  }
});
