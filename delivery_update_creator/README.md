# 🚀 DELIVERY AGENT REGISTRATION FIX - EXECUTION PLAN

## 📋 OVERVIEW
This folder contains all SQL scripts needed to fix the delivery agent and restaurant registration process with correct English roles.

---

## 🎯 EXECUTION ORDER

Execute these scripts **IN ORDER** in your Supabase SQL Editor:

### **1️⃣ STEP 1: Create Registration RPCs**
**File:** `01_create_registration_rpcs.sql`

**What it does:**
- ✅ Creates `register_delivery_agent_v2()` RPC with role `'delivery_agent'`
- ✅ Creates `register_restaurant_v2()` RPC with role `'restaurant'`
- ✅ Creates `register_client_v2()` RPC with role `'client'`
- ✅ All functions return JSON with success/error messages

**Expected output:**
```
✅ CREATE FUNCTION register_delivery_agent_v2
✅ CREATE FUNCTION register_restaurant_v2
✅ CREATE FUNCTION register_client_v2
```

---

### **2️⃣ STEP 2: Verify Status Fields**
**File:** `02_add_status_fields.sql`

**What it does:**
- ✅ Verifies `status` column exists in `delivery_agent_profiles`
- ✅ Verifies `status` column exists in `restaurants`
- ⚠️ **NOTE:** Status fields ALREADY EXIST in your database, so this script only verifies (no modifications)

**Expected output:**
```
✅ delivery_agent_profiles.status EXISTS (no changes needed)
✅ restaurants.status EXISTS (no changes needed)
✅ All status fields exist. No modifications needed.
```

---

### **3️⃣ STEP 3: Update Master Signup Trigger**
**File:** `03_update_master_handle_signup.sql`

**What it does:**
- ✅ Drops ALL previous versions of `master_handle_signup()`
- ✅ Recreates trigger function with:
  - English roles: `'client'`, `'delivery_agent'`, `'restaurant'`, `'admin'`
  - No references to `OLD.status` (fixes the error)
  - Proper address/geolocation handling
  - Proper vehicle_type/license_plate handling
  - Proper restaurant_name/restaurant_address handling

**Expected output:**
```
✅ DROP FUNCTION master_handle_signup
✅ CREATE FUNCTION master_handle_signup
✅ Function handles all 4 roles correctly
```

---

### **4️⃣ STEP 4: Verification**
**File:** `04_verify_setup.sql`

**What it does:**
- ✅ Verifies all 3 registration RPCs exist
- ✅ Verifies `master_handle_signup()` trigger exists
- ✅ Verifies status columns exist in all profile tables
- ✅ Shows current trigger configuration

**Expected output:**
```
✅ 3 registration functions found
✅ 1 master_handle_signup function found
✅ Status columns exist in all tables
✅ Trigger is properly attached to auth.users
```

---

## 📊 SUMMARY

| Step | File | Purpose | Impact |
|------|------|---------|--------|
| 1 | `01_create_registration_rpcs.sql` | Create registration functions | Backend API ready |
| 2 | `02_add_status_fields.sql` | Verify status columns exist | Status validation |
| 3 | `03_update_master_handle_signup.sql` | Fix signup trigger | Handles all roles correctly |
| 4 | `04_verify_setup.sql` | Verify everything works | Validation |

---

## 🔧 AFTER RUNNING SCRIPTS

Once all 4 scripts are executed successfully, the frontend changes will be applied automatically.

**Frontend files that will be updated:**
- `lib/screens/public/delivery_agent_registration_screen.dart`
- `lib/screens/public/restaurant_registration_screen.dart`
- `lib/screens/auth/register_screen.dart`

**Changes:**
- ✅ Roles changed from Spanish to English
- ✅ Correct RPC calls for each registration type
- ✅ Proper error handling

---

## ✅ SUCCESS CRITERIA

After execution, you should be able to:
1. ✅ Register a new delivery agent with `'delivery_agent'` role
2. ✅ Register a new restaurant with `'restaurant'` role
3. ✅ Register a new client with `'client'` role
4. ✅ All profiles get `status='pending_approval'` or `status='active'`
5. ✅ Email verification works correctly
6. ✅ No "record 'old' has no field 'status'" errors

---

## 🆘 TROUBLESHOOTING

If any script fails:
1. Copy the **entire error message**
2. Note which step failed
3. Share with the development team for quick resolution

---

**Created:** 2025-01-XX  
**Version:** 1.0  
**Compatibility:** Supabase PostgreSQL 15+
