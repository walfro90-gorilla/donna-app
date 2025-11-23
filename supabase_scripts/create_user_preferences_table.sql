-- =====================================================
-- TABLA: user_preferences
-- Descripción: Almacena preferencias del usuario incluyendo estado de onboarding
-- =====================================================

-- Crear tabla si no existe
CREATE TABLE IF NOT EXISTS user_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  has_seen_onboarding BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para optimizar consultas
CREATE INDEX IF NOT EXISTS idx_user_preferences_user_id ON user_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_user_preferences_onboarding ON user_preferences(has_seen_onboarding);

-- Trigger para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_user_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_user_preferences_updated_at ON user_preferences;
CREATE TRIGGER trigger_update_user_preferences_updated_at
  BEFORE UPDATE ON user_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_user_preferences_updated_at();

-- Comentarios para documentación
COMMENT ON TABLE user_preferences IS 'Almacena preferencias y estado de onboarding del usuario';
COMMENT ON COLUMN user_preferences.user_id IS 'ID del usuario (FK a users)';
COMMENT ON COLUMN user_preferences.has_seen_onboarding IS 'Indica si el usuario ya vio el onboarding/bienvenida';
COMMENT ON COLUMN user_preferences.created_at IS 'Timestamp de creación del registro';
COMMENT ON COLUMN user_preferences.updated_at IS 'Timestamp de última actualización';

-- RLS (Row Level Security) policies
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

-- Policy: Los usuarios pueden ver solo sus propias preferencias
DROP POLICY IF EXISTS "Users can view own preferences" ON user_preferences;
CREATE POLICY "Users can view own preferences" ON user_preferences
  FOR SELECT
  USING (auth.uid() = user_id);

-- Policy: Los usuarios pueden insertar sus propias preferencias
DROP POLICY IF EXISTS "Users can insert own preferences" ON user_preferences;
CREATE POLICY "Users can insert own preferences" ON user_preferences
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Policy: Los usuarios pueden actualizar sus propias preferencias
DROP POLICY IF EXISTS "Users can update own preferences" ON user_preferences;
CREATE POLICY "Users can update own preferences" ON user_preferences
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Policy: Los admins pueden ver todas las preferencias
DROP POLICY IF EXISTS "Admins can view all preferences" ON user_preferences;
CREATE POLICY "Admins can view all preferences" ON user_preferences
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Mensaje de confirmación
DO $$
BEGIN
  RAISE NOTICE '✅ Tabla user_preferences creada exitosamente con RLS habilitado';
END $$;
