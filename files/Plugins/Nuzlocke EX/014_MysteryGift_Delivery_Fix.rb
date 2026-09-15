#===============================================================================
# Añil - Arreglo de la ENTREGA de Regalos Misteriosos
#===============================================================================
# El NPC "Repartidor" (Liga Pokémon / Torre Batalla) tiene 3 páginas:
#   - Página 0 (sin condición)            -> Evento Común 18 (desbloquear)
#   - Página 1 (switch 150 ON)            -> Evento Común 19 ("no tengo nada")
#   - Página 2 (switch 150 ON + 30 ON)    -> Evento Común 20 (ENTREGAR el regalo)
#
# Problema: en este build NADA encendía los switches 150 ni 30 (verificado en
# todos los mapas, eventos comunes y scripts). Como en RPG Maker XP los switches
# arrancan en false, el Repartidor se quedaba siempre en la página 0 y nunca podía
# ENTREGAR un regalo ya descargado.
#
# Estos dos switches se usan EXCLUSIVAMENTE por el Repartidor, así que aquí los
# mantenemos sincronizados al entrar a cualquier mapa:
#   - switch 150 = el jugador tiene desbloqueado el Regalo Misterioso
#   - switch  30 = hay al menos un regalo descargado pendiente de recoger
# Con esto el Repartidor pasa solo a su página de entrega cuando toca.
#===============================================================================

module AnilMysteryGiftFix
  UNLOCKED_SWITCH = 150
  PENDING_SWITCH  = 30

  module_function

  def sync
    return if !$player || !$game_switches
    unlocked = $player.respond_to?(:mystery_gift_unlocked) && $player.mystery_gift_unlocked
    pending  = false
    begin
      pending = (pbNextMysteryGiftID > 0)
    rescue
      pending = false
    end
    changed = false
    if $game_switches[UNLOCKED_SWITCH] != unlocked
      $game_switches[UNLOCKED_SWITCH] = unlocked
      changed = true
    end
    if $game_switches[PENDING_SWITCH] != pending
      $game_switches[PENDING_SWITCH] = pending
      changed = true
    end
    # Forzar re-evaluación de las páginas de eventos si algo cambió, para que el
    # Repartidor cambie de página sin tener que salir y volver al mapa.
    $game_map.need_refresh = true if changed && $game_map
  end
end

EventHandlers.add(:on_enter_map, :anil_mystery_gift_sync, proc { |_prev|
  AnilMysteryGiftFix.sync
})
