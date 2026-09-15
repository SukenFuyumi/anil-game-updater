#===============================================================================
# Intercambiador de Repetidos (Añil)
#  Un "Don Prodigio de repetidos": el Magnemite de Ciudad Plateada (mapa 9, evento 18,
#  junto al centro Pokémon) te da un Pokémon ALEATORIO (randomizado como el reto) a cambio
#  de un Pokémon REPETIDO tuyo. Solo se pueden entregar repetidos (anti-trampa/exploit).
#
#  "Repetido" = ya tienes otro de su MISMA FAMILIA evolutiva en equipo + PC + cementerio
#  (los muertos cuentan: viven en las cajas con @perma_faint). Así, si se te murió uno y te
#  sale por fósil, cuenta como repetido y puedes intercambiarlo o quedártelo.
#===============================================================================

# Nivel del Pokémon que entrega el intercambiador.
ANIL_TRADER_LEVEL = 5

# --- Detección de repetidos ------------------------------------------------------

# Todos los Pokémon del jugador (equipo + todas las cajas del PC, vivos y muertos).
# pbEachPokemon recorre equipo + almacenamiento; los muertos viven en cajas con @perma_faint.
def pbAnilAllOwnedPokemon
  list = []
  pbEachPokemon { |pkmn, _box| list.push(pkmn) if pkmn }
  return list
rescue
  ($player && $player.party) ? $player.party.compact : []
end

# Ids de la familia evolutiva de un Pokémon (línea completa).
def pbAnilFamilyIds(pkmn)
  return [] if !pkmn
  sd = pkmn.species_data
  return (sd.get_family_species rescue [pkmn.species])
end

# Clave cronológica de obtención: el MENOR = el ORIGINAL (más antiguo). timeReceived es un
# entero (timestamp Unix); personalID desempata para que siempre haya un único original.
def pbAnilObtainKey(pkmn)
  t   = (pkmn.instance_variable_get(:@timeReceived) || 0)
  pid = ((pkmn.respond_to?(:personalID) ? pkmn.personalID : 0) || 0)
  return [t, pid]
end

# ¿Este Pokémon es "repetido"? = existe OTRO de su familia (equipo+PC+cementerio) obtenido
# ANTES que él. Así el PRIMERO/original de cada familia NO se marca como repetido; solo las
# copias posteriores (p. ej. el mismo Pokémon que te sale luego por fósil).
def pbAnilDuplicate?(pkmn)
  return false if !pkmn
  fam = pbAnilFamilyIds(pkmn)
  return false if fam.empty?
  mykey = pbAnilObtainKey(pkmn)
  pbAnilAllOwnedPokemon.each do |p|
    next if !p || p.equal?(pkmn)
    next unless fam.any? { |s| p.isSpecies?(s) }
    return true if (pbAnilObtainKey(p) <=> mykey) < 0   # hay uno de la familia más antiguo
  end
  return false
rescue
  return false
end

# ¿Se puede ENTREGAR este Pokémon al intercambiador? (repetido, vivo, no huevo, y sin dejarte sin equipo)
def pbAnilTradeEligible?(pk)
  return false if !pk || pk.egg? || pk.perma_faint
  return false if !$player || !$player.party || $player.party.length <= 1
  return pbAnilDuplicate?(pk)
rescue
  return false
end

# --- Reward aleatorio ------------------------------------------------------------

def pbAnilRandomRewardSpecies
  keys = GameData::Species.keys
  30.times do
    cand = keys.sample
    sd = (GameData::Species.get(cand) rescue nil)
    next if !sd || sd.form != 0
    return sd.species
  end
  return :RATTATA # último recurso improbable
end

# --- El intercambiador -----------------------------------------------------------

def pbAnilDuplicateTrader
  pbMessage(_INTL("¡Zzzzt! El Magnemite proyecta una señal magnética...\nParece atraer a los Pokémon REPETIDOS."))
  # ¿Tiene el jugador algún repetido intercambiable en el EQUIPO? (los del PC hay que sacarlos)
  has_dup = ($player.party || []).any? { |p| pbAnilTradeEligible?(p) }
  if !has_dup
    pbMessage(_INTL("No llevas ningún Pokémon repetido en tu equipo.\n(Si lo tienes en el PC, retíralo primero.)"))
    return
  end
  if !pbConfirmMessage(_INTL("Te dará un Pokémon misterioso a cambio de uno REPETIDO de tu equipo.\n¿Quieres intercambiar?"))
    pbMessage(_INTL("El Magnemite se aleja flotando. ¡Zzzt!"))
    return
  end
  chosen = -1
  pbFadeOutIn(99999) {
    scene  = PokemonParty_Scene.new
    screen = PokemonPartyScreen.new(scene, $player.party)
    # Anotación APTO / NO APTO bajo cada Pokémon (solo los repetidos son APTO).
    annot = $player.party.map { |p| pbAnilTradeEligible?(p) ? _INTL("APTO") : _INTL("NO APTO") }
    screen.pbStartScene(_INTL("Elige un Pokémon REPETIDO (APTO) para entregar."), false, annot)
    loop do
      idx = screen.pbChoosePokemon
      if idx < 0
        chosen = -1
        break
      end
      pk = $player.party[idx]
      next if !pk
      if !pbAnilTradeEligible?(pk)
        # Feedback claro de por qué NO es apto.
        reason = if pk.egg?                     then _INTL("es un Huevo")
                 elsif pk.perma_faint           then _INTL("está debilitado permanentemente")
                 elsif $player.party.length <= 1 then _INTL("es tu último Pokémon")
                 else                                _INTL("no es repetido (es el original)")
                 end
        screen.pbDisplay(_INTL("NO APTO: {1} {2}.", pk.name, reason))
        next
      end
      if screen.pbConfirm(_INTL("{1} es APTO. ¿Entregarlo a cambio de uno misterioso?", pk.name))
        chosen = idx
        break
      end
    end
    screen.pbEndScene
  }
  return if chosen < 0
  given = $player.party[chosen]
  # Genera el reward: especie aleatoria, randomizada por el reto (ability/moves vía alias).
  level = ANIL_TRADER_LEVEL
  level = given.level if !level || level <= 0
  reward = Pokemon.new(pbAnilRandomRewardSpecies, level)
  reward.heal rescue nil
  # Marca de origen: viene del Intercambiador de Repetidos (Magnemite).
  reward.anil_origin = :magnemite if reward.respond_to?(:anil_origin=)
  # Registro de intercambio (entregado -> recibido) para la lista de "entregados".
  AnilOrigin.record_given(given, reward, _INTL("NPC de repetidos")) if defined?(AnilOrigin)
  # Reemplaza en el mismo hueco del equipo.
  $player.party[chosen] = reward
  $player.pokedex.register(reward) rescue nil
  $player.pokedex.set_owned(reward.species) rescue nil
  pbMessage(_INTL("¡Entregaste a {1}!", given.name))
  (pbSEPlay("Battle catch click") rescue nil)
  reward.play_cry rescue nil
  pbMessage(_INTL("¡Recibiste un {1} misterioso a cambio!", reward.speciesName))
end

#===============================================================================
# Hook del Magnemite (mapa 9, evento 18) SIN editar el mapa: interceptamos la
# interacción del jugador. Es el patrón fiable (a diferencia de :on_player_interact,
# que no se dispara si hay un evento delante).
#===============================================================================
ANIL_TRADER_MAP_ID   = 9
ANIL_TRADER_EVENT_ID = 18

class Game_Player
  alias __anil_trader_cett check_event_trigger_there unless method_defined?(:__anil_trader_cett)
  def check_event_trigger_there(triggers)
    if $game_map && $game_map.map_id == ANIL_TRADER_MAP_ID &&
       !$game_system.map_interpreter.running? && triggers.include?(0)
      ev = $game_map.events[ANIL_TRADER_EVENT_ID]
      if ev
        nx = @x + (@direction == 6 ? 1 : @direction == 4 ? -1 : 0)
        ny = @y + (@direction == 2 ? 1 : @direction == 8 ? -1 : 0)
        facing = ev.at_coordinate?(nx, ny)
        # Soporte para mostrador (counter): un tile más allá.
        if !facing && $game_map.counter?(nx, ny)
          nx2 = nx + (@direction == 6 ? 1 : @direction == 4 ? -1 : 0)
          ny2 = ny + (@direction == 2 ? 1 : @direction == 8 ? -1 : 0)
          facing = ev.at_coordinate?(nx2, ny2)
        end
        if facing && !ev.jumping? && !ev.over_trigger?
          $game_player.straighten rescue nil
          pbAnilDuplicateTrader
          return true
        end
      end
    end
    return __anil_trader_cett(triggers)
  end
end
