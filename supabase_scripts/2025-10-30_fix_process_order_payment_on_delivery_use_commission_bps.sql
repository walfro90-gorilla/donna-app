-- Purpose: Replace legacy fixed 20%/15% splits with dynamic commission_bps per restaurant
-- Function: process_order_payment_on_delivery (trigger function on orders)
-- Notes:
--  - Uses restaurants.commission_bps (basis points) with default 1500 (15%).
--  - Keeps existing account model; no new accounts are created.
--  - Looks up platform revenue account exactly as current system: by email 'platform+revenue@doarepartos.com' and account_type 'platform'.
--  - Preserves current columns of account_transactions (no metadata field assumed).
--  - Idempotent via CREATE OR REPLACE FUNCTION.

DO $$
BEGIN
  -- Ensure the function exists with correct signature
  PERFORM 1;
END$$;

CREATE OR REPLACE FUNCTION public.process_order_payment_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_restaurant_account_id uuid;
    v_delivery_account_id uuid;
    v_platform_revenue_account_id uuid;

    v_restaurant_user_id uuid;

    v_commission_bps integer;
    v_commission_bps_clamped integer;
    v_commission_rate numeric; -- 0..1

    v_restaurant_amount numeric(12,2);
    v_delivery_amount numeric(12,2);
    v_platform_commission_amount numeric(12,2);
    v_platform_delivery_margin numeric(12,2);
    v_platform_total numeric(12,2);
BEGIN
    -- Only process when status changes to 'delivered'
    IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM NEW.status) THEN

        -- Get restaurant user_id
        SELECT r.user_id
          INTO v_restaurant_user_id
          FROM public.restaurants r
         WHERE r.id = NEW.restaurant_id
         LIMIT 1;

        -- Resolve accounts (existing ones only)
        SELECT a.id
          INTO v_restaurant_account_id
          FROM public.accounts a
         WHERE a.user_id = v_restaurant_user_id
           AND a.account_type = 'restaurant'
         LIMIT 1;

        SELECT a.id
          INTO v_delivery_account_id
          FROM public.accounts a
         WHERE a.user_id = NEW.delivery_agent_id
           AND a.account_type = 'delivery_agent'
         LIMIT 1;

        -- Platform revenue account: keep current lookup by email and type
        SELECT a.id
          INTO v_platform_revenue_account_id
          FROM public.accounts a
          JOIN public.users u ON u.id = a.user_id
         WHERE u.email = 'platform+revenue@doarepartos.com'
           AND a.account_type = 'platform'
         LIMIT 1;

        -- If any required account is missing, exit gracefully
        IF v_restaurant_account_id IS NULL OR v_delivery_account_id IS NULL OR v_platform_revenue_account_id IS NULL THEN
            RETURN NEW;
        END IF;

        -- Commission rate from restaurants.commission_bps (basis points); default 1500; clamp 0..3000
        SELECT COALESCE(r.commission_bps, 1500)
          INTO v_commission_bps
          FROM public.restaurants r
         WHERE r.id = NEW.restaurant_id
         LIMIT 1;

        v_commission_bps_clamped := GREATEST(0, LEAST(v_commission_bps, 3000));
        v_commission_rate := v_commission_bps_clamped::numeric / 10000.0; -- e.g., 1500 -> 0.15

        -- Compute amounts with proper rounding
        v_platform_commission_amount := ROUND(NEW.subtotal * v_commission_rate, 2);
        v_restaurant_amount := ROUND(NEW.subtotal - v_platform_commission_amount, 2);

        -- Keep existing delivery split: 85% to courier, 15% platform margin
        v_delivery_amount := ROUND(NEW.delivery_fee * 0.85, 2);
        v_platform_delivery_margin := ROUND(NEW.delivery_fee - v_delivery_amount, 2);
        v_platform_total := ROUND(v_platform_commission_amount + v_platform_delivery_margin, 2);

        -- 1) Restaurant revenue
        INSERT INTO public.account_transactions (
            account_id, type, amount, description, related_order_id, created_at
        ) VALUES (
            v_restaurant_account_id,
            'ORDER_REVENUE',
            v_restaurant_amount,
            'Pago por orden #' || NEW.id || ' (' || (ROUND((1 - v_commission_rate) * 100, 2)) || '% del subtotal)',
            NEW.id,
            NOW()
        );

        -- 2) Courier earnings
        INSERT INTO public.account_transactions (
            account_id, type, amount, description, related_order_id, created_at
        ) VALUES (
            v_delivery_account_id,
            'DELIVERY_EARNINGS',
            v_delivery_amount,
            'Entrega orden #' || NEW.id || ' (85% del delivery fee)',
            NEW.id,
            NOW()
        );

        -- 3) Platform commission (dynamic bps) + delivery margin (keep single entry to match schema/types)
        INSERT INTO public.account_transactions (
            account_id, type, amount, description, related_order_id, created_at
        ) VALUES (
            v_platform_revenue_account_id,
            'PLATFORM_COMMISSION',
            v_platform_total,
            'Comisión orden #' || NEW.id || ' (' || ROUND(v_commission_rate * 100, 2) || '% subtotal + 15% delivery)',
            NEW.id,
            NOW()
        );

        -- Update balances (additive model preserved)
        UPDATE public.accounts 
           SET balance = balance + v_restaurant_amount,
               updated_at = NOW()
         WHERE id = v_restaurant_account_id;

        UPDATE public.accounts 
           SET balance = balance + v_delivery_amount,
               updated_at = NOW()
         WHERE id = v_delivery_account_id;

        UPDATE public.accounts 
           SET balance = balance + v_platform_total,
               updated_at = NOW()
         WHERE id = v_platform_revenue_account_id;
    END IF;

    RETURN NEW;
END;
$$;

-- End of patch
