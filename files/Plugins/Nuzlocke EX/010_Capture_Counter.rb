#===============================================================================
# Contador de Capturas (Añil) — datos de apoyo
#  - Marca guardable en cada Pokémon para identificar "capturas extra".
#  - Helper para saber si la zona actual ya tiene su captura (para el indicador).
#===============================================================================
class Pokemon
  # true = se capturó como "captura extra" (en una zona que ya tenía captura registrada)
  attr_accessor :anil_extra_capture
end

class Battle
  # true = en este combate el jugador ya confirmó que quiere capturar de más (captura extra).
  # Al ser un objeto Battle nuevo por combate, no hace falta reiniciarlo.
  attr_accessor :anil_extra_pending
end

module ChallengeModes
  module_function

  # true = Contador de Capturas activo EN SOLITARIO (sin las cláusulas estrictas de
  # "Una captura por mapa"/"Primer Pokémon"). Es el modo de aviso suave: solo la hierba
  # consume zona; regalos/fósiles/intercambios/huevos nunca se bloquean ni cuentan.
  def counter_only?
    return on?(:CAPTURE_COUNTER) && !on?(:FIRST_CAPTURE) && !on?(:ONE_CAPTURE)
  end

  # ¿La zona actual ya tiene registrada su captura? (para el indicador de Pokébola)
  # Sirve tanto para ONE_CAPTURE/FIRST_CAPTURE como para CAPTURE_COUNTER,
  # porque had_first_encounter? ya filtra por regla activa y mapas divididos.
  def zone_captured?
    return had_first_encounter?
  end

  # Cuenta cuántas capturas extra llevas (equipo + cajas). Para mostrar/depurar.
  def extra_capture_count
    n = 0
    pbEachPokemon { |pkmn, _| n += 1 if pkmn.respond_to?(:anil_extra_capture) && pkmn.anil_extra_capture }
    return n
  rescue
    return 0
  end

  # ¿La zona ACTUAL es de captura rastreable? (hay una regla de captura activa y el mapa
  # tiene encuentros o forma parte de una zona dividida). Para el letrero de cambio de zona.
  def current_zone_trackable?
    return false if !(on?(:CAPTURE_COUNTER) || on?(:ONE_CAPTURE) || on?(:FIRST_CAPTURE))
    return false if !$game_map
    mid = $game_map.map_id
    return true if (GameData::Encounter.exists?(mid) rescue false)
    return true if SPLIT_MAPS_FOR_ENCOUNTERS[mid]
    SPLIT_MAPS_FOR_ENCOUNTERS.each { |_p, kids| return true if kids.include?(mid) }
    return false
  end

  # ¿El jugador ya visitó este mapa (o alguno de sus mapas hijo/padre)? Sirve para mostrar
  # solo las zonas ACCESIBLES según su progreso actual.
  def zone_visited_for_map?(map_id)
    return false if !$PokemonGlobal || !$PokemonGlobal.visitedMaps
    vis = $PokemonGlobal.visitedMaps
    return true if vis[map_id]
    if SPLIT_MAPS_FOR_ENCOUNTERS[map_id]
      SPLIT_MAPS_FOR_ENCOUNTERS[map_id].each { |c| return true if vis[c] }
    end
    SPLIT_MAPS_FOR_ENCOUNTERS.each do |parent, kids|
      if kids.include?(map_id)
        return true if vis[parent]
        kids.each { |c| return true if vis[c] }
        break
      end
    end
    return false
  end

  # ¿Un MAPA concreto ya tiene registrada su captura? (versión de had_first_encounter?
  # para un map_id arbitrario, teniendo en cuenta mapas divididos padre/hijo).
  def zone_captured_for_map?(map_id)
    return false if !$PokemonGlobal || !$PokemonGlobal.challenge_encs
    encs = $PokemonGlobal.challenge_encs
    return true if encs[map_id]
    if SPLIT_MAPS_FOR_ENCOUNTERS[map_id]
      SPLIT_MAPS_FOR_ENCOUNTERS[map_id].each { |c| return true if encs[c] }
    end
    SPLIT_MAPS_FOR_ENCOUNTERS.each do |parent, kids|
      if kids.include?(map_id)
        return true if encs[parent]
        kids.each { |c| return true if encs[c] }
        break
      end
    end
    return false
  end
end

#===============================================================================
# Pantalla "Capturas por zona" (dentro del juego): muestra qué zonas de encuentro
# aún tienes PENDIENTES de captura y cuáles ya hiciste. Se abre desde el menú de pausa.
#===============================================================================

# Devuelve [ [nombre_zona, :pending|:captured], ... ]. Agrupa mapas hijos en su padre,
# omite mapas sin nombre real y SOLO incluye zonas que el jugador YA VISITÓ (accesibles
# según su progreso). Pendientes primero, luego alfabético.
def pbAnilCaptureZones
  return [] if !$PokemonGlobal
  child_to_parent = {}
  ChallengeModes::SPLIT_MAPS_FOR_ENCOUNTERS.each do |parent, kids|
    kids.each { |k| child_to_parent[k] = parent }
  end
  seen = {}
  zones = []
  GameData::Encounter.each do |enc|
    mid = enc.map
    zid = child_to_parent[mid] || mid
    next if seen[zid]
    seen[zid] = true
    next if !ChallengeModes.zone_visited_for_map?(zid)   # solo lugares accesibles ya visitados
    name = (pbGetMapNameFromId(zid) rescue "")
    next if nil_or_empty?(name)
    cap = ChallengeModes.zone_captured_for_map?(zid)
    zones << [name, cap ? :captured : :pending]
  end
  zones.sort_by! { |z| [z[1] == :pending ? 0 : 1, z[0]] }
  return zones
end

# Ventana de lista con icono de Poké Ball por fila (gris = pendiente, color = capturada).
class Window_AnilCaptureList < Window_CommandPokemon
  ICON = 24
  def anil_set_statuses(arr)
    @anil_status = arr
    refresh
  end
  def anil_icon(status)
    @anil_icons ||= {}
    key = (status == :captured) ? "icon_own" : "icon_own_gray"
    return @anil_icons[key] if @anil_icons.key?(key)
    bmp = (AnimatedBitmap.new("Graphics/Pictures/DP Pause Menu/#{key}") rescue nil)
    @anil_icons[key] = bmp
    bmp
  end
  def drawItem(index, _count, rect)
    pbSetSystemFont(self.contents) if @starting
    rect = drawCursor(index, rect)
    tx = rect.x
    st = @anil_status ? @anil_status[index] : nil
    if st
      ab = anil_icon(st)
      if ab && ab.bitmap
        y = rect.y + (rect.height - ICON) / 2
        self.contents.stretch_blt(Rect.new(rect.x, y, ICON, ICON), ab.bitmap,
                                  Rect.new(0, 0, ab.bitmap.width, ab.bitmap.height))
      end
      tx = rect.x + ICON + 6
    end
    pbDrawShadowText(self.contents, tx, rect.y + (self.contents.text_offset_y || 0),
                     rect.width - (tx - rect.x), rect.height, @commands[index],
                     self.baseColor, self.shadowColor)
  end
  def dispose
    @anil_icons&.each_value { |b| b&.dispose }
    super
  end
end

# Muestra la lista desplazable de zonas con su estado (iconos de Poké Ball).
def pbAnilShowCaptureStatus
  zones = pbAnilCaptureZones
  if zones.empty?
    pbMessage(_INTL("Aún no has llegado a ninguna zona de captura."))
    return
  end
  pending  = zones.count { |z| z[1] == :pending }
  captured = zones.length - pending
  names    = zones.map { |name, _st| name }
  statuses = zones.map { |_name, st| st }
  pbMessage(_INTL("Capturas por zona (lugares visitados).\nPendientes: {1}   ·   Hechas: {2}", pending, captured))
  vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
  vp.z = 99999
  cmdwin = Window_AnilCaptureList.newWithSize(names, 0, 0, Graphics.width, Graphics.height, vp)
  cmdwin.anil_set_statuses(statuses)
  loop do
    Graphics.update
    Input.update
    cmdwin.update
    pbUpdateSceneMap
    break if Input.trigger?(Input::BACK) || Input.trigger?(Input::USE)
  end
  cmdwin.dispose
  vp.dispose
end
