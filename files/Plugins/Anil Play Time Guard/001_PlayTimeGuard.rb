#===============================================================================
# Anil Play Time Guard
#-------------------------------------------------------------------------------
# Blinda el contador de tiempo de juego ($stats.play_time) contra reinicios
# accidentales (p.ej. un GameStats nuevo por abrir el save en distinto build).
#
# Guarda un "máximo histórico" del tiempo en $PokemonGlobal, que NO se reinicia
# junto con $stats. Al cargar, si el tiempo viene más bajo que ese máximo, lo
# restaura. Es puramente aditivo y a prueba de fallos:
#   - No toca ningún script del core.
#   - Marshal-tolerante: un save viejo/original sin el atributo carga igual
#     (el getter devuelve 0.0 por defecto) sin crashear ni restaurar de más.
#   - Todos los hooks van envueltos en rescue: ante cualquier error, no hace
#     nada y el juego sigue normal.
#===============================================================================

module AnilPlayTimeGuard
  # Margen en segundos. Si el tiempo cargado es más bajo que el máximo histórico
  # por más de este margen, se considera un reinicio y se restaura.
  RESTORE_THRESHOLD = 30.0

  module_function

  # Sube el máximo histórico si el tiempo actual lo supera.
  def sync_high
    return unless $stats && $PokemonGlobal
    cur = $stats.play_time.to_f
    hi  = $PokemonGlobal.anil_play_time_high.to_f
    $PokemonGlobal.anil_play_time_high = cur if cur > hi
  rescue => e
    echoln "AnilPlayTimeGuard.sync_high error: #{e.message}"
  end

  # Al cargar: si el tiempo cargado cayó muy por debajo del máximo, restaura.
  def restore_if_reset
    return unless $stats && $PokemonGlobal
    cur = $stats.play_time.to_f
    hi  = $PokemonGlobal.anil_play_time_high.to_f
    if hi > cur + RESTORE_THRESHOLD
      $stats.instance_variable_set(:@play_time, hi)
      echoln "AnilPlayTimeGuard: tiempo restaurado de #{cur.to_i}s a #{hi.to_i}s"
    elsif cur > hi
      $PokemonGlobal.anil_play_time_high = cur
    end
  rescue => e
    echoln "AnilPlayTimeGuard.restore_if_reset error: #{e.message}"
  end
end

#-------------------------------------------------------------------------------
# Atributo persistente en $PokemonGlobal (patrón estándar de plugins Essentials).
#-------------------------------------------------------------------------------
class PokemonGlobalMetadata
  attr_writer :anil_play_time_high

  def anil_play_time_high
    @anil_play_time_high ||= 0.0
  end
end

#-------------------------------------------------------------------------------
# Hooks en Game.load / Game.save.
#-------------------------------------------------------------------------------
module Game
  class << self
    if method_defined?(:load) && !method_defined?(:__anil_ptg_load)
      alias __anil_ptg_load load
    end
    if method_defined?(:save) && !method_defined?(:__anil_ptg_save)
      alias __anil_ptg_save save
    end
  end

  def self.load(save_data)
    __anil_ptg_load(save_data)
    AnilPlayTimeGuard.restore_if_reset
  end

  def self.save(*args)
    AnilPlayTimeGuard.sync_high # deja el máximo fresco antes de escribir el save
    __anil_ptg_save(*args)
  end
end

#-------------------------------------------------------------------------------
# Mantiene el máximo al día mientras se juega (coste despreciable).
#-------------------------------------------------------------------------------
EventHandlers.add(:on_frame_update, :anil_play_time_guard,
  proc {
    AnilPlayTimeGuard.sync_high
  }
)
