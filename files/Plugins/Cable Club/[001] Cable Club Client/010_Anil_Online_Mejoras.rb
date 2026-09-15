#===============================================================================
# Añil Online — Mejoras (por Suken)
#  - Entrar al online hablando con el Kadabra del Centro Pokémon de Azulona.
#  - Editor de EVs para combates online (IVs fijos en 31). Los EVs se aplican al
#    entrar al online y los Pokémon RECUPERAN sus stats originales al salir.
#  - Presets de EVs del equipo: guardar y volver a aplicar sin reescribir todo.
#  (El código de sala flexible se cambió en 006_CableClub_UI.rb.)
#===============================================================================

# Log de diagnóstico del online. DESACTIVADO en la build final (no escribe nada).
# Para reactivarlo al depurar, pon ANIL_ONLINE_DEBUG_LOG = true.
ANIL_ONLINE_DEBUG_LOG = false unless defined?(ANIL_ONLINE_DEBUG_LOG)
def pbAnilLog(msg)
  return unless ANIL_ONLINE_DEBUG_LOG
  begin
    File.open("online_debug.txt", "a") { |f| f.puts("#{Time.now.strftime('%H:%M:%S')}  #{msg}") }
  rescue
  end
end

module AnilOnlineEV
  STATS   = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
  LABELS  = ["PS", "Ataque", "Defensa", "At. Esp.", "Def. Esp.", "Velocidad"]
  MAX_PER_STAT = 252
  MAX_TOTAL    = 510
  PRESET_DIR   = "OnlineEVPresets"

  # Bandera de tiempo de ejecución (NO se guarda): true mientras hay una sesión online viva.
  # Distingue una sesión viva de un respaldo huérfano tras un cierre/crash (para restaurar al cargar).
  @online_active = false
  class << self; attr_accessor :online_active; end

  module_function

  # ---- plan de EVs actual (persiste en la partida) -------------------------
  # Estructura: array de 6 hashes { stat_sym => valor }. Índice = posición en el equipo.
  def plan
    $PokemonGlobal.anil_ev_plan ||= []
    $PokemonGlobal.anil_ev_plan
  end

  def plan_for(index)
    plan[index] ||= empty_spread
    plan[index]
  end

  def empty_spread
    h = {}; STATS.each { |s| h[s] = 0 }; h
  end

  def total(spread)
    STATS.sum { |s| spread[s] || 0 }
  end

  # Máximo que puedes poner en una stat sin pasarte de 252 ni de 510 en total.
  def max_allowed(spread, stat)
    used_other = total(spread) - (spread[stat] || 0)
    [MAX_PER_STAT, MAX_TOTAL - used_other].min
  end

  def effective_nature_name(pkmn)
    n = pkmn.respond_to?(:nature_for_stats) ? pkmn.nature_for_stats : pkmn.nature
    n ? n.name : "—"
  rescue
    "—"
  end

  # ---- aplicar / restaurar --------------------------------------------------
  # Guarda IV/EV originales una sola vez, pone IVs=31 y los EVs del plan, recalcula.
  # Guarda los IV/EV originales DENTRO de cada Pokémon (@anil_iv_orig/@anil_ev_orig), pone
  # IVs=31 y los EVs del plan, y recalcula. Guardar el respaldo en el propio Pokémon lo hace
  # a prueba de guardar/cargar (las referencias no se comparten entre $player y $PokemonGlobal
  # tras un Marshal) y a prueba de intercambios/reordenamientos: el respaldo viaja con el mon.
  def apply_to_party
    return if $PokemonGlobal.anil_ev_backup # ya aplicado en esta sesión
    $player.party.each_with_index do |pkmn, i|
      next if pkmn.instance_variable_get(:@anil_iv_orig) # ya respaldado (por si acaso)
      pkmn.instance_variable_set(:@anil_iv_orig, pkmn.iv.clone)
      pkmn.instance_variable_set(:@anil_ev_orig, pkmn.ev.clone)
      spread = plan[i] || empty_spread
      GameData::Stat.each_main { |s| pkmn.iv[s.id] = 31 }
      STATS.each { |s| pkmn.ev[s] = (spread[s] || 0) }
      pkmn.calc_stats
      # PP MAX en el online (igualdad de condiciones): respalda PP y PP Ups de cada
      # movimiento y los pone al máximo. Se restaura al salir (viaja con el Pokémon).
      apply_pp_max(pkmn)
    end
    $PokemonGlobal.anil_ev_backup = true
  end

  # Respalda [pp, ppup] de cada movimiento y los maximiza (PP Ups a 3 + PP lleno).
  def apply_pp_max(pkmn)
    return if !pkmn || pkmn.instance_variable_get(:@anil_pp_orig)
    bak = (pkmn.moves || []).map { |m| m ? [m.pp, m.ppup] : nil }
    pkmn.instance_variable_set(:@anil_pp_orig, bak)
    (pkmn.moves || []).each do |m|
      next if !m
      m.ppup = 3
      m.pp   = m.total_pp
    end
  rescue
  end

  # Restaura desde el respaldo que cada Pokémon lleva consigo. Recorre TODO (equipo + cajas)
  # para no dejar ninguno con stats temporales, aunque se haya depositado/movido.
  def restore_one(pkmn)
    return false unless pkmn
    io = pkmn.instance_variable_get(:@anil_iv_orig)
    eo = pkmn.instance_variable_get(:@anil_ev_orig)
    po = pkmn.instance_variable_get(:@anil_pp_orig)
    return false unless io || eo || po
    io.each { |k, v| pkmn.iv[k] = v } if io
    eo.each { |k, v| pkmn.ev[k] = v } if eo
    # Restaura PP y PP Ups originales (los PP nunca por encima del máximo real).
    if po
      (pkmn.moves || []).each_with_index do |m, i|
        next if !m || !po[i]
        m.ppup = po[i][1]
        m.pp   = [po[i][0], m.total_pp].min
      end
      pkmn.instance_variable_set(:@anil_pp_orig, nil)
    end
    pkmn.instance_variable_set(:@anil_iv_orig, nil)
    pkmn.instance_variable_set(:@anil_ev_orig, nil)
    pkmn.calc_stats
    true
  rescue
    false
  end

  def restore_party
    # Equipo + cajas.
    pbEachPokemon { |pkmn, _box| restore_one(pkmn) } rescue nil
    # + el equipo ORIGINAL que los combates random guardan aparte ($original_player_party),
    #   que pbEachPokemon NO recorre. Sin esto, esos Pokémon quedaban con IVs 31/EVs 0.
    (defined?($original_player_party) && $original_player_party || []).each { |pkmn| restore_one(pkmn) } rescue nil
    # + el equipo actual, por si acaso alguno no estaba en el almacenamiento en ese instante.
    ($player && $player.party ? $player.party : []).each { |pkmn| restore_one(pkmn) } rescue nil
    $PokemonGlobal.anil_ev_backup = nil if $PokemonGlobal
  end

  # ¿Queda algún Pokémon con respaldo de EV/IV pendiente (equipo + cajas + equipo original)?
  # Sirve para la auto-curación al cambiar de mapa, incluso si la bandera ya se limpió.
  def has_pending_backup?
    (($player && $player.party) ? $player.party : []).each { |pk| return true if pk && pk.instance_variable_get(:@anil_iv_orig) }
    (defined?($original_player_party) && $original_player_party || []).each { |pk| return true if pk && pk.instance_variable_get(:@anil_iv_orig) }
    found = false
    pbEachPokemon { |pk, _| found = true if pk && pk.instance_variable_get(:@anil_iv_orig) } rescue nil
    found
  rescue
    false
  end

  # ---- presets (archivos en OnlineEVPresets/) -------------------------------
  def preset_files
    Dir.mkdir(PRESET_DIR) unless Dir.exist?(PRESET_DIR)
    Dir.chdir(PRESET_DIR) { Dir.glob("*.evset") }
  rescue
    []
  end

  def save_preset(name)
    Dir.mkdir(PRESET_DIR) unless Dir.exist?(PRESET_DIR)
    File.open(sprintf("%s/%s.evset", PRESET_DIR, name), "w") do |f|
      $player.party.each_with_index do |pkmn, i|
        spread = plan[i] || empty_spread
        vals = STATS.map { |s| spread[s] || 0 }.join(",")
        f.puts("#{pkmn.speciesName};#{vals}")
      end
    end
    true
  rescue => e
    pbMessage(_INTL("No pude guardar el preset: {1}", e.message)); false
  end

  def delete_preset(filename)
    File.delete(sprintf("%s/%s", PRESET_DIR, filename))
    true
  rescue => e
    pbMessage(_INTL("No pude borrar el preset: {1}", e.message)); false
  end

  def load_preset(filename)
    lines = File.readlines(sprintf("%s/%s", PRESET_DIR, filename))
    lines.each_with_index do |line, i|
      next unless plan[i] ||= empty_spread
      vals = line.chomp.split(";").last.to_s.split(",").map(&:to_i)
      STATS.each_with_index { |s, j| plan[i][s] = (vals[j] || 0) }
    end
    true
  rescue => e
    pbMessage(_INTL("No pude cargar el preset: {1}", e.message)); false
  end
end

class PokemonGlobalMetadata
  attr_accessor :anil_ev_plan, :anil_ev_backup
end

#===============================================================================
# Editor de EVs (usa la UI estándar del juego para máxima fiabilidad)
#===============================================================================
def pbAnilEditEVsForMon(index)
  pkmn = $player.party[index]
  return unless pkmn
  spread = AnilOnlineEV.plan_for(index)
  # Sprite del Pokémon visible durante toda la edición (menú de stats y entrada de EVs).
  spr_vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
  spr_vp.z = 99000
  spr = (PokemonIconSprite.new(pkmn, spr_vp) rescue nil)
  if spr
    spr.setOffset(PictureOrigin::CENTER) rescue nil
    spr.x = 60
    spr.y = 64
  end
  begin
    loop do
      used = AnilOnlineEV.total(spread)
      cmds = []
      AnilOnlineEV::STATS.each_with_index do |s, i|
        cmds.push(sprintf("%s: %d", AnilOnlineEV::LABELS[i], spread[s]))
      end
      cmds.push(_INTL("Poner todo a 0"))
      cmds.push(_INTL("Listo"))
      title = _INTL("{1} · IVs fijos 31 · Nat. {2}\nEV usados: {3}/{4}",
                    pkmn.name, AnilOnlineEV.effective_nature_name(pkmn), used, AnilOnlineEV::MAX_TOTAL)
      cmd = pbMessage(title, cmds, cmds.length - 1)   # cancelar = "Listo"
      if cmd < 0 || cmd == cmds.length - 1        # Listo / cancelar
        break
      elsif cmd == cmds.length - 2                # Poner todo a 0
        AnilOnlineEV::STATS.each { |s| spread[s] = 0 }
      else
        stat = AnilOnlineEV::STATS[cmd]
        maxv = AnilOnlineEV.max_allowed(spread, stat)
        # Entrada por TECLADO: escribe el número de EVs directamente (caja vacía, sin el 0).
        # Helptext corto (stat + rango) para que no se entrecorte.
        # mode=2 + pkmn => la pantalla de entrada dibuja el sprite del Pokémon de forma nativa
        # (esa pantalla hace su propio pbFadeOutIn, así que un overlay externo no se vería).
        entry = pbEnterText(_INTL("{1}  (0-{2})", AnilOnlineEV::LABELS[cmd], maxv),
                            0, [maxv.to_s.length, 3].max, "", 2, pkmn)
        if entry && !entry.strip.empty?
          val = entry.to_i
          val = 0 if val < 0
          val = maxv if val > maxv
          spread[stat] = val
        end
      end
    end
  ensure
    spr.dispose if spr && !spr.disposed?
    spr_vp.dispose if spr_vp && !spr_vp.disposed?
  end
end

# Ventana de comandos con icono de Pokémon por fila (nil = sin icono, p.ej. filas de preset).
class Window_AnilEVList < Window_CommandPokemon
  ICON = 32
  def anil_set_mons(list)
    @anil_mons = list
    @anil_cache ||= {}
    refresh
  end
  def anil_bitmap(pkmn)
    return nil if !pkmn
    @anil_cache ||= {}
    key = pkmn.object_id
    return @anil_cache[key] if @anil_cache.key?(key)
    bmp = (AnimatedBitmap.new(GameData::Species.icon_filename_from_pokemon(pkmn)) rescue nil)
    @anil_cache[key] = bmp
    bmp
  end
  def drawItem(index, _count, rect)
    pbSetSystemFont(self.contents) if @starting
    rect = drawCursor(index, rect)
    tx = rect.x
    pkmn = @anil_mons ? @anil_mons[index] : nil
    ab = anil_bitmap(pkmn)
    if ab && ab.bitmap
      fw = ab.bitmap.height   # hoja horizontal: frame cuadrado = alto de la imagen
      y = rect.y + (rect.height - ICON) / 2
      self.contents.stretch_blt(Rect.new(rect.x, y, ICON, ICON), ab.bitmap, Rect.new(0, 0, fw, ab.bitmap.height))
      tx = rect.x + ICON + 6
    end
    pbDrawShadowText(self.contents, tx, rect.y + (self.contents.text_offset_y || 0),
                     rect.width - (tx - rect.x), rect.height, @commands[index],
                     self.baseColor, self.shadowColor)
  end
  def dispose
    @anil_cache&.each_value { |b| b&.dispose }
    super
  end
end

# Selector interactivo con iconos de Pokémon. Devuelve el índice elegido o -1 (cancelar).
def pbAnilChooseWithIcons(cmds, mons, init = 0)
  vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
  vp.z = 99999
  win = Window_AnilEVList.newWithSize(cmds, 0, 0, Graphics.width, Graphics.height, vp)
  win.anil_set_mons(mons)
  win.index = init if init >= 0 && init < cmds.length
  ret = -1
  loop do
    Graphics.update
    Input.update
    win.update
    pbUpdateSceneMap
    if Input.trigger?(Input::USE)
      pbPlayDecisionSE
      ret = win.index
      break
    elsif Input.trigger?(Input::BACK)
      pbPlayCancelSE
      ret = -1
      break
    end
  end
  win.dispose
  vp.dispose
  return ret
end

def pbAnilEVEditor
  header_shown = false
  loop do
    party = $player.party
    cmds = []
    mons = []
    party.each_with_index do |pkmn, i|
      used = AnilOnlineEV.total(AnilOnlineEV.plan_for(i))
      cmds.push(sprintf("%s  (%d/%d)", pkmn.name, used, AnilOnlineEV::MAX_TOTAL))
      mons.push(pkmn)
    end
    idxGuardar = cmds.length; cmds.push(_INTL("💾 Guardar preset")); mons.push(nil)
    idxCargar  = cmds.length; cmds.push(_INTL("📂 Cargar preset"));  mons.push(nil)
    idxBorrar  = cmds.length; cmds.push(_INTL("🗑 Eliminar preset")); mons.push(nil)
    idxReset   = cmds.length; cmds.push(_INTL("Reiniciar EVs de todos")); mons.push(nil)
    idxSalir   = cmds.length; cmds.push(_INTL("Salir")); mons.push(nil)
    if !header_shown
      pbMessage(_INTL("Editor de EVs para el online (IVs fijos en 31)."))
      header_shown = true
    end
    cmd = pbAnilChooseWithIcons(cmds, mons, 0)
    if cmd < 0 || cmd == idxSalir
      break
    elsif cmd == idxGuardar
      name = pbEnterText(_INTL("Nombre del preset:"), 1, 16)
      AnilOnlineEV.save_preset(name) && pbMessage(_INTL("Preset '{1}' guardado.", name)) if name && !name.empty?
    elsif cmd == idxCargar
      files = AnilOnlineEV.preset_files
      if files.empty?
        pbMessage(_INTL("No tienes presets guardados todavía."))
      else
        names = files.map { |f| f.sub(/\.evset$/, "") }
        pick = pbMessage(_INTL("¿Qué preset cargar?"), names + [_INTL("Cancelar")], names.length)
        if pick >= 0 && pick < files.length
          AnilOnlineEV.load_preset(files[pick]) && pbMessage(_INTL("Preset '{1}' cargado.", names[pick]))
        end
      end
    elsif cmd == idxBorrar
      files = AnilOnlineEV.preset_files
      if files.empty?
        pbMessage(_INTL("No tienes presets guardados todavía."))
      else
        names = files.map { |f| f.sub(/\.evset$/, "") }
        pick = pbMessage(_INTL("¿Qué preset eliminar?"), names + [_INTL("Cancelar")], names.length)
        if pick >= 0 && pick < files.length
          if pbConfirmMessage(_INTL("¿Seguro que quieres eliminar el preset '{1}'?", names[pick]))
            AnilOnlineEV.delete_preset(files[pick]) && pbMessage(_INTL("Preset '{1}' eliminado.", names[pick]))
          end
        end
      end
    elsif cmd == idxReset
      if pbConfirmMessage(_INTL("¿Reiniciar los EVs de TODO el equipo a 0?"))
        party.each_with_index { |_p, i| AnilOnlineEV.plan[i] = AnilOnlineEV.empty_spread }
      end
    else
      pbAnilEditEVsForMon(cmd)
    end
  end
end

#===============================================================================
# Menú del Kadabra (entrada al online)
#===============================================================================
def pbAnilOnlineMenu
  loop do
    cmd = pbMessage(_INTL("Un misterioso Alakazam proyecta un enlace psíquico...\n¿Qué quieres hacer?"),
      [_INTL("Combatir online"),
       _INTL("Editar EVs del equipo"),
       _INTL("Salir")], 3)
    case cmd
    when 0
      pbAnilStartOnline
    when 1
      pbAnilEVEditor
    else
      break
    end
  end
end

# Aplica los EVs del plan, entra al online, y RESTAURA los stats al salir.
def pbAnilStartOnline
  if !pbConfirmMessage(_INTL("Se aplicarán tus EVs elegidos y los IVs quedarán en 31 para los combates online. Al salir, tus Pokémon volverán a la normalidad. ¿Continuar?"))
    return
  end
  # Neutraliza los modos LOCALES que afectan el combate (VGC/dobles, Inverso), para que el
  # formato online lo defina SOLO lo negociado y ambos jugadores estén sincronizados.
  # (Sin esto: si uno juega en dobles y otro en singles, cada pantalla ve un formato distinto.)
  saved_modes = {}
  [["MODO_VGC", 147], ["MODO_INVERSO", nil], ["MODO_SIN_GRINDEO", nil]].each do |name, fallback|
    sw = (Object.const_defined?(name) ? Object.const_get(name) : fallback)
    next unless sw && $game_switches
    saved_modes[sw] = $game_switches[sw]
    $game_switches[sw] = false
  end
  # Turbo OFF durante el online (evita desyncs por velocidad distinta entre jugadores).
  saved_gamespeed = $GameSpeed rescue 0
  # Guardamos DÓNDE estamos para volver aquí al terminar. Como ahora se entra desde el menú
  # de pausa (cualquier mapa) y el combate te transfiere a la sala online (mapa 218), nadie
  # nos devolvería si no guardáramos el origen. (Antes se entraba desde un evento fijo.)
  $anil_online_return = [$game_map.map_id, $game_player.x, $game_player.y, $game_player.direction] rescue nil
  begin
    AnilOnlineEV.online_active = true
    $GameSpeed = 0 rescue nil
    $CanToggle = false rescue nil
    AnilOnlineEV.apply_to_party
    $player.connecting_online = true
    pbCableClub
  ensure
    $player.connecting_online = false
    AnilOnlineEV.restore_party
    saved_modes.each { |sw, val| $game_switches[sw] = val }
    AnilOnlineEV.online_active = false
    # El retorno (con fundido) va ANTES de restaurar el turbo, para que el fade se vea a
    # velocidad normal y no "en turbo" (demasiado rápido / feo).
    pbAnilReturnFromOnline
    $GameSpeed = (saved_gamespeed || 0) rescue nil
    ($CanToggle = ($PokemonSystem.only_speedup_battles == 0)) rescue nil
  end
  pbMessage(_INTL("Has salido del online. Tus Pokémon recuperaron sus estadísticas originales."))
end

# Devuelve al jugador a donde estaba antes de entrar al online (si fue transferido a la sala
# de combate/intercambio) y limpia los switches de sala. Seguro aunque no se haya movido.
def pbAnilReturnFromOnline
  in_room = false
  in_room = true if defined?(SWITCH_ONLINE_COMBATE) && $game_switches[SWITCH_ONLINE_COMBATE]
  in_room = true if defined?(SWITCH_ONLINE_INTERCAMBIO) && $game_switches[SWITCH_ONLINE_INTERCAMBIO]
  ret = $anil_online_return
  if ret && ret[0] && (in_room || $game_map.map_id != ret[0])
    pbFadeOutIn(99999) {
      $game_temp.player_new_map_id    = ret[0]
      $game_temp.player_new_x         = ret[1]
      $game_temp.player_new_y         = ret[2]
      $game_temp.player_new_direction = ret[3] || 2
      pbDismountBike rescue nil
      $scene.transfer_player
      $game_map.autoplay
      $game_map.refresh
    }
  end
  $game_switches[SWITCH_ONLINE_COMBATE] = false if defined?(SWITCH_ONLINE_COMBATE)
  $game_switches[SWITCH_ONLINE_INTERCAMBIO] = false if defined?(SWITCH_ONLINE_INTERCAMBIO)
  $anil_online_return = nil
end

# (El acceso al online es ahora SOLO por la opción "Online" del menú de pausa.
#  Se quitó el enganche del Kadabra de Azulona.)

#===============================================================================
# Turbo OFF durante el online (refuerzo por-frame: ni con la tecla se activa)
#===============================================================================
EventHandlers.add(:on_frame_update, :anil_no_turbo_online, proc {
  if ($player && $player.connecting_online?) || AnilOnlineEV.online_active
    $GameSpeed = 0 rescue nil
    $CanToggle = false rescue nil
  end
})

# Refuerzo DEFINITIVO del turbo online: on_frame_update NO corre durante el combate, así que
# también interceptamos Input.update (que sí corre cada frame en TODAS las escenas, batalla
# incluida). Si el turbo se pudiera activar en un combate online, los dos clientes correrían a
# distinta velocidad y se DESINCRONIZARÍAN (pantalla negra / expulsión). Aquí lo forzamos OFF.
module Input
  class << self
    alias_method :__anil_preturbo_update, :update unless method_defined?(:__anil_preturbo_update)
    def update
      if ($player && $player.connecting_online?) || (defined?(AnilOnlineEV) && AnilOnlineEV.online_active)
        $GameSpeed = 0
        $CanToggle = false
      end
      __anil_preturbo_update
    end
  end
end

#===============================================================================
# Blindaje anti-crash: si al cargar/entrar a un mapa hay un respaldo de EVs pendiente
# y NO estamos en una sesión online viva (p. ej. el juego se cerró a media conexión),
# restaura los IV/EV originales automáticamente.
#===============================================================================
EventHandlers.add(:on_enter_map, :anil_restore_ev_backup, proc { |_prev|
  if !AnilOnlineEV.online_active
    # Auto-curación: restaura si la bandera sigue puesta (cierre/crash a media conexión) O si
    # queda CUALQUIER Pokémon con respaldo pendiente aunque la bandera ya se hubiera limpiado
    # (recupera fugas de versiones anteriores y las que dejó fuera el barrido antiguo).
    if $PokemonGlobal && ($PokemonGlobal.anil_ev_backup || AnilOnlineEV.has_pending_backup?)
      AnilOnlineEV.restore_party
    end
    # Y por si un Game.save durante el online (p.ej. tras un intercambio) dejó pegada la bandera
    # de conexión: fuera de una sesión viva, connecting_online SIEMPRE debe estar en false.
    $player.connecting_online = false if $player && $player.connecting_online?

    # ANTI-ATASCO: si una desconexión abnormal dejó al jugador en la sala de combate online
    # (mapa 218) o con los switches de sala pegados, lo sacamos a donde estaba y limpiamos todo.
    begin
      combate = (defined?(SWITCH_ONLINE_COMBATE) && $game_switches && $game_switches[SWITCH_ONLINE_COMBATE])
      interc  = (defined?(SWITCH_ONLINE_INTERCAMBIO) && $game_switches && $game_switches[SWITCH_ONLINE_INTERCAMBIO])
      en_sala = combate || interc || ($game_map && $game_map.map_id == 218)
      if en_sala
        dest = nil
        if $anil_online_return && $anil_online_return[0]
          dest = $anil_online_return                      # a donde estaba antes de entrar al online
        elsif $game_map && $game_map.map_id == 218 && $PokemonGlobal && $PokemonGlobal.healingSpot
          hs = $PokemonGlobal.healingSpot                 # respaldo: último Centro Pokémon [map,x,y]
          dest = [hs[0], hs[1], hs[2], 2]
        end
        if dest && dest[0]
          pbFadeOutIn(99999) {
            $game_temp.player_new_map_id    = dest[0]
            $game_temp.player_new_x         = dest[1]
            $game_temp.player_new_y         = dest[2]
            $game_temp.player_new_direction = dest[3] || 2
            pbDismountBike rescue nil
            $scene.transfer_player
            $game_map.autoplay
            $game_map.refresh
          }
          $anil_online_return = nil
        end
      end
      $game_switches[SWITCH_ONLINE_COMBATE] = false if defined?(SWITCH_ONLINE_COMBATE) && $game_switches
      $game_switches[SWITCH_ONLINE_INTERCAMBIO] = false if defined?(SWITCH_ONLINE_INTERCAMBIO) && $game_switches
    rescue
    end
  end
})

#===============================================================================
# Acceso universal: opción "Combate Online" en el menú de pausa (además del Kadabra),
# para poder entrar desde cualquier Centro Pokémon (y cualquier lugar).
#===============================================================================
MenuHandlers.add(:pause_menu, :anil_online, {
  "name"      => _INTL("Combate Online"),
  "order"     => 75,
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    pbFadeOutIn do
      pbAnilOnlineMenu
      pbUpdateSceneMap
      menu.pbRefresh
    end
    next false
  }
})
