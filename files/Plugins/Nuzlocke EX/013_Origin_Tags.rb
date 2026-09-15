#===============================================================================
# Marcas de ORIGEN (Añil) — cómo obtuviste cada Pokémon
#
#  Añade, junto a las marcas ya existentes "Captura EXTRA" y "Repetido", una marca
#  de ORIGEN por Pokémon:
#     • Primer de ruta   (1ª captura legítima de una zona)
#     • Fósil            (revivido de un fósil)
#     • Intercambio NPC  (obtain_method == 2)
#     • Don Prodigio     (intercambio cuyo Pokémon llega con OT "Don Prodigio")
#     • Centro comercial / Estático / ...  (dados por evento; ver tabla STATIC_EVENTS)
#
#  Además lleva un REGISTRO de los Pokémon que ENTREGASTE (a intercambios NPC, a
#  Don Prodigio y al Intercambiador de Repetidos), consultable desde el menú.
#
#  Todo se guarda DENTRO de cada Pokémon (sobrevive a guardar/cargar). Los estáticos
#  guardan (mapa, evento) para poder etiquetarlos por evento concreto (tabla abajo).
#===============================================================================

class Pokemon
  attr_accessor :anil_origin        # símbolo de origen si se dio por evento (:fossil/:static/...)
  attr_accessor :anil_first_route   # true = fue la primera captura legítima de su zona
  attr_accessor :anil_origin_map    # map_id donde se obtuvo por evento (para clasificar estáticos)
  attr_accessor :anil_origin_event  # event_id que lo entregó (para clasificar estáticos)
end

class PokemonGlobalMetadata
  attr_accessor :anil_given_log     # array de hashes: Pokémon que entregaste
end

module AnilOrigin
  module_function

  # --- Tabla de estáticos por evento -------------------------------------------
  # Traduce [map_id, event_id] -> símbolo de etiqueta. Se rellena en Fase 2 con los
  # ids que el propio juego muestra al obtener cada estático (ver ANIL_ORIGIN_DEBUG).
  # Ejemplo: [7, 12] => :centro_comercial
  STATIC_EVENTS = {
    [40, 25]  => :fossil,         # Museo Pokémon: reviver de fósiles
    [118, 25] => :fossil,         # Laboratorio Canela: reviver de fósiles
    [118, 26] => :fossil,         # Laboratorio Canela: combinador de fósiles
    [70, 13]  => :magikarp_500,   # Centro Pokémon: vendedor de Magikarp
    [80, 20]  => :regalo,         # Edificio Azulona: Eevee
    [102, 97] => :regalo,         # Silph S.A: Lapras
    [117, 10] => :regalo,         # Dojo Azafrán
    [117, 11] => :regalo,         # Dojo Azafrán
    [202, 14] => :regalo,         # Bill
    [203, 7]  => :regalo,         # Riolu
    [205, 6]  => :regalo,         # Casa (regalo)
    [206, 8]  => :regalo,         # Casa (regalo)
    [207, 7]  => :regalo,         # Dojo Magenta
    [29, 11]  => :regalo,         # Laboratorio: legendarios (Gabriel)
    [28, 26]  => :starter,        # Iniciales (Azul)
    [30, 23]  => :starter,        # Iniciales
    [29, 28]  => :starter,        # Iniciales (selección)
    [29, 29]  => :starter,
    [29, 30]  => :starter,
  }

  # Etiquetas mostrables por símbolo de origen.
  LABELS = {
    :first_route      => "Primer de ruta",
    :fossil           => "Fósil",
    :npc_trade        => "Intercambio NPC",
    :don_prodigio     => "Don Prodigio",
    :magnemite        => "Intercambiador de repetidos",
    :centro_comercial => "Centro comercial",
    :magikarp_500     => "Comprado (Magikarp)",
    :casino           => "Premio del casino",
    :regalo           => "Regalo",
    :starter          => "Inicial",
    :static           => "Estático"
  }

  # OT exacto del Pokémon que entrega Don Prodigio.
  DON_PRODIGIO_OT = "Don Prodigio"

  # Poner en true para que el juego avise (mapa, evento, especie) al obtener un
  # estático — así identificas cada evento sin abrir RMXP. Dejar en false en la build.
  ANIL_ORIGIN_DEBUG = false unless defined?(ANIL_ORIGIN_DEBUG)

  # Id del evento que se está ejecutando ahora (el que entrega el Pokémon).
  def running_event_id
    itp = ($game_system && $game_system.respond_to?(:map_interpreter)) ? $game_system.map_interpreter : nil
    return 0 if !itp
    (itp.instance_variable_get(:@event_id) || 0)
  rescue
    0
  end

  def current_map_id
    ($game_map ? $game_map.map_id : 0) rescue 0
  end

  # Marca un Pokémon recién dado por EVENTO (regalo/estático/fósil/centro comercial...).
  def tag_event_pokemon(pkmn)
    return if !pkmn || !pkmn.is_a?(Pokemon)
    return if pkmn.egg?                       # los huevos ya se distinguen por obtain_method
    map = current_map_id
    ev  = running_event_id
    pkmn.anil_origin_map   = map
    pkmn.anil_origin_event = ev
    # Respeta un origen ya asignado por quien lo entrega (p. ej. el casino).
    return if pkmn.anil_origin
    if $PokemonGlobal && $PokemonGlobal.reviving_fossil
      pkmn.anil_origin = :fossil
    else
      pkmn.anil_origin = STATIC_EVENTS[[map, ev]] || :static
    end
    if ANIL_ORIGIN_DEBUG
      pbMessage(_INTL("[ORIGEN] {1}: mapa={2}, evento={3}, tipo={4}",
                      pkmn.speciesName, map, ev, pkmn.anil_origin.to_s)) rescue nil
    end
  rescue
  end

  # Clasificación de ORIGEN para mostrar (prioridad de más específico a más general).
  # Devuelve un símbolo de LABELS o nil (si no hay origen especial que mostrar).
  def classify(pkmn)
    return nil if !pkmn
    # Intercambios (obtain_method 2): Don Prodigio se distingue por su OT.
    if pkmn.obtain_method == 2
      ot = (pkmn.owner && pkmn.owner.name) ? pkmn.owner.name : ""
      return :don_prodigio if ot == DON_PRODIGIO_OT
      return :npc_trade
    end
    # Dado por evento (tiene origen guardado).
    return pkmn.anil_origin if pkmn.anil_origin && LABELS.key?(pkmn.anil_origin)
    # Capturado: primera captura legítima de la zona.
    return :first_route if pkmn.anil_first_route
    return nil
  rescue
    return nil
  end

  def label(pkmn)
    sym = classify(pkmn)
    return nil if !sym
    txt = LABELS[sym]
    return txt ? _INTL(txt) : nil
  end

  # --- Registro de Pokémon ENTREGADOS ------------------------------------------
  def given_log
    return [] if !$PokemonGlobal
    $PokemonGlobal.anil_given_log ||= []
    $PokemonGlobal.anil_given_log
  end

  # --- Migración retroactiva (una sola vez por partida) -------------------------
  # Los Pokémon obtenidos ANTES de esta actualización no tienen datos de origen.
  # Lo único recuperable con fiabilidad es "Primer de ruta": el Pokémon CAPTURADO más
  # antiguo de cada mapa (que no sea repetido). Intercambios/Don Prodigio ya se deducen
  # por obtain_method/OT sin migración. Fósiles/estáticos antiguos NO son recuperables.
  def retro_migrate
    return if !$PokemonGlobal
    return if $PokemonGlobal.instance_variable_get(:@anil_origin_migrated)
    $PokemonGlobal.instance_variable_set(:@anil_origin_migrated, true)
    by_map = {}
    pbEachPokemon do |pkmn, _box|
      next if !pkmn || pkmn.egg?
      next if pkmn.obtain_method != 0                       # solo capturados
      next if pkmn.anil_first_route || pkmn.anil_origin     # ya tiene marca
      m = pkmn.obtain_map
      next if !m || m == 0
      # Solo mapas que son zona de captura registrada (evita marcar regalos de pueblo).
      next if ChallengeModes.respond_to?(:zone_captured_for_map?) && !ChallengeModes.zone_captured_for_map?(m)
      key = [(pkmn.timeReceived ? pkmn.timeReceived.to_i : 0), (pkmn.personalID || 0)]
      if !by_map[m] || (key <=> by_map[m][0]) < 0
        by_map[m] = [key, pkmn]
      end
    end
    by_map.each_value do |(_key, pkmn)|
      next if (defined?(pbAnilDuplicate?) && pbAnilDuplicate?(pkmn)) rescue false
      pkmn.anil_first_route = true if pkmn.respond_to?(:anil_first_route=)
    end
  rescue
    $PokemonGlobal.instance_variable_set(:@anil_origin_migrated, true) if $PokemonGlobal
  end

  # Instantánea de un Pokémon (lo justo para el texto y el icono).
  def snapshot(pkmn)
    return nil if !pkmn
    {
      :species     => pkmn.species,
      :speciesName => (pkmn.speciesName rescue pkmn.species.to_s),
      :name        => (pkmn.name rescue ""),
      :level       => (pkmn.level rescue 0),
      :form        => (pkmn.form rescue 0),
      :gender      => (pkmn.gender rescue 0),
      :shiny       => (pkmn.shiny? rescue false),
      :egg         => (pkmn.egg? rescue false)
    }
  rescue
    nil
  end

  # Registra un intercambio: Pokémon ENTREGADO -> Pokémon RECIBIDO (y a quién).
  def record_given(given, recv = nil, to_name = "")
    return if !given || !$PokemonGlobal
    $PokemonGlobal.anil_given_log ||= []
    $PokemonGlobal.anil_given_log.push({
      :given => snapshot(given),
      :recv  => snapshot(recv),
      :to    => to_name.to_s,
      :map   => current_map_id,
      :time  => (Time.now.to_i rescue 0)
    })
  rescue
  end
end

#===============================================================================
# Hooks de OBTENCIÓN POR EVENTO (regalos/estáticos/fósiles/centro comercial...).
# Encadenamos sobre los alias de "005 Capture Rules": normalizamos a un objeto
# Pokémon y lo pasamos a super (así el objeto ALMACENADO es el mismo que marcamos).
#===============================================================================
class Object
  [:pbAddPokemon, :pbAddPokemonSilent, :pbAddToParty, :pbAddToPartySilent,
   :pbAddForeignPokemon].each do |meth|
    next if !private_method_defined?(meth) && !method_defined?(meth)
    alias_name = "__anilorigin_#{meth}".to_sym
    next if private_method_defined?(alias_name) || method_defined?(alias_name)
    alias_method(alias_name, meth)
    define_method(meth) do |*args|
      return send(alias_name, *args) if !args[0]
      pkmn = args[0]
      pkmn = Pokemon.new(pkmn, args[1]) if !pkmn.is_a?(Pokemon)
      args[0] = pkmn   # garantiza identidad hasta el almacenamiento
      ret = send(alias_name, *args)
      AnilOrigin.tag_event_pokemon(pkmn) if ret != false
      ret
    end
    private meth
  end
end

#===============================================================================
# Hook de INTERCAMBIOS NPC (pbStartTrade): registra el Pokémon ENTREGADO.
# El recibido se detecta por obtain_method==2 / OT (no hace falta hook para mostrarlo).
# Se instala DE FORMA DIFERIDA porque pbStartTrade lo define otro plugin que carga
# más tarde; así garantizamos envolver la versión final y no una inexistente.
#===============================================================================
module AnilOrigin
  def self.push_given(given_snap, recv, to_name)
    return if !given_snap || !$PokemonGlobal
    $PokemonGlobal.anil_given_log ||= []
    $PokemonGlobal.anil_given_log.push({
      :given => given_snap, :recv => snapshot(recv),
      :to => to_name.to_s, :map => current_map_id, :time => (Time.now.to_i rescue 0)
    })
  rescue
  end

  @trade_hook_installed = false
  def self.install_trade_hook
    return if @trade_hook_installed
    @trade_hook_installed = true
    # Intercambio con entrenador (equipo): pbStartTrade.
    if Object.private_method_defined?(:pbStartTrade) || Object.method_defined?(:pbStartTrade)
      Object.send(:alias_method, :__anilorigin_pbStartTrade, :pbStartTrade)
      Object.send(:define_method, :pbStartTrade) do |pokemonIndex, newpoke, nickname, trainerName, trainerGender = 0|
        given_snap = AnilOrigin.snapshot(($player && $player.party) ? $player.party[pokemonIndex] : nil)
        ret = __anilorigin_pbStartTrade(pokemonIndex, newpoke, nickname, trainerName, trainerGender)
        recv = ($player && $player.party) ? $player.party[pokemonIndex] : nil
        AnilOrigin.push_given(given_snap, recv, trainerName)
        ret
      end
      Object.send(:private, :pbStartTrade)
    end
    # Intercambio desde el PC (el más usado en Añil): pbStartTradePC. El Pokémon entregado
    # sale del almacenamiento en la posición pbGet(1) ([caja, índice]).
    if Object.private_method_defined?(:pbStartTradePC) || Object.method_defined?(:pbStartTradePC)
      Object.send(:alias_method, :__anilorigin_pbStartTradePC, :pbStartTradePC)
      Object.send(:define_method, :pbStartTradePC) do |newpoke, trainerGender = 0, level = 0, nickname = nil, trainerName = nil|
        pos = (pbGet(1) rescue nil)
        given = nil
        given = ($PokemonStorage[pos[0], pos[1]] rescue nil) if pos.is_a?(Array)
        given_snap = AnilOrigin.snapshot(given)
        ret = __anilorigin_pbStartTradePC(newpoke, trainerGender, level, nickname, trainerName)
        recv = nil
        recv = ($PokemonStorage[pos[0], pos[1]] rescue nil) if pos.is_a?(Array)
        to = trainerName
        to ||= (recv && recv.owner ? recv.owner.name : nil) rescue nil
        to ||= _INTL("Intercambio NPC")
        AnilOrigin.push_given(given_snap, recv, to)
        ret
      end
      Object.send(:private, :pbStartTradePC)
    end
  rescue
    @trade_hook_installed = true   # no reintentar en bucle si algo falla
  end
end

EventHandlers.add(:on_frame_update, :anil_install_trade_hook,
                  proc { AnilOrigin.install_trade_hook })

# Migración retroactiva de "Primer de ruta" para partidas anteriores a esta feature.
# Se ejecuta una sola vez, cuando ya hay partida cargada.
EventHandlers.add(:on_frame_update, :anil_origin_retro_migrate,
                  proc { AnilOrigin.retro_migrate if $PokemonGlobal })

#===============================================================================
# Pantalla "Pokémon entregados" (desde el menú): qué ENTREGASTE -> qué RECIBISTE,
# con los sprites (iconos) de ambos y a quién se lo diste.
#===============================================================================
class Window_AnilGivenList < Window_CommandPokemon
  ICON = 24

  def anil_set_entries(entries)
    @anil_entries = entries
    @anil_icons ||= {}
    refresh
  end

  def anil_icon(snap)
    return nil if !snap
    @anil_icons ||= {}
    key = [snap[:species], snap[:form] || 0, snap[:gender] || 0, snap[:shiny] ? 1 : 0]
    return @anil_icons[key] if @anil_icons.key?(key)
    path = (GameData::Species.icon_filename(snap[:species], snap[:form] || 0,
             snap[:gender] || 0, snap[:shiny] || false) rescue nil)
    path ||= (GameData::Species.icon_filename(snap[:species]) rescue nil)
    ab = (path ? (AnimatedBitmap.new(path) rescue nil) : nil)
    @anil_icons[key] = ab
    ab
  end

  def blit_icon(snap, x, y)
    ab = anil_icon(snap)
    return if !ab || !ab.bitmap
    fw = ab.bitmap.height   # primer frame (el icono es cuadrado)
    self.contents.stretch_blt(Rect.new(x, y, ICON, ICON), ab.bitmap, Rect.new(0, 0, fw, fw))
  end

  def anil_name(snap)
    return "?" if !snap
    nil_or_empty?(snap[:name]) ? (snap[:speciesName] || snap[:species].to_s) : snap[:name]
  end

  def anil_text(x, ty, h, str)
    w = self.contents.text_size(str).width
    pbDrawShadowText(self.contents, x, ty, w + 4, h, str, self.baseColor, self.shadowColor)
    return w
  end

  def drawItem(index, _count, rect)
    pbSetSystemFont(self.contents) if @starting
    rect = drawCursor(index, rect)
    e  = @anil_entries ? @anil_entries[index] : nil
    return if !e
    ty = rect.y + (self.contents.text_offset_y || 0)
    iy = rect.y + (rect.height - ICON) / 2
    x  = rect.x
    # [sprite entregado] nombre  ->  [sprite recibido] nombre  (a quién)
    blit_icon(e[:given], x, iy);  x += ICON + 4
    x += anil_text(x, ty, rect.height, anil_name(e[:given])) + 10
    x += anil_text(x, ty, rect.height, ">>") + 10
    blit_icon(e[:recv], x, iy);   x += ICON + 4
    x += anil_text(x, ty, rect.height, anil_name(e[:recv])) + 12
    to = nil_or_empty?(e[:to]) ? _INTL("un entrenador") : e[:to]
    anil_text(x, ty, rect.height, _INTL("({1})", to))
  end

  def dispose
    @anil_icons&.each_value { |b| b&.dispose }
    super
  end
end

def pbAnilShowGivenAway
  log = AnilOrigin.given_log
  # Solo entradas con el formato nuevo (entregado -> recibido).
  entries = (log || []).select { |e| e.is_a?(Hash) && e[:given] }.reverse
  if entries.empty?
    pbMessage(_INTL("Aún no has entregado ningún Pokémon en intercambios."))
    return
  end
  lines = entries.map { "" }   # el dibujado es custom (iconos + nombres) en drawItem
  pbMessage(_INTL("Has entregado {1} Pokémon en intercambios:", entries.length))
  vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
  vp.z = 99999
  win = Window_AnilGivenList.newWithSize(lines, 0, 0, Graphics.width, Graphics.height, vp)
  win.anil_set_entries(entries)
  loop do
    Graphics.update
    Input.update
    win.update
    pbUpdateSceneMap
    break if Input.trigger?(Input::BACK) || Input.trigger?(Input::USE)
  end
  win.dispose
  vp.dispose
end
