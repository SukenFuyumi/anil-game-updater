#===============================================================================
# Añil — Plaza Online (semi-MMO Fase 1)  ·  por Suken (+ asistente)
#-------------------------------------------------------------------------------
#  Un HUB donde ves a otros jugadores DEL MISMO MODO (normal / nuzlocke /
#  randomlocke), puedes CHATEAR y RETAR a combate. Los combates NO pasan por
#  este servicio: cuando dos se retan, el servidor del hub (puerto 25566) solo
#  reparte un CÓDIGO y ambos entran al Cable Club de siempre (25565).
#
#  DISEÑO NO INVASIVO:
#   - Es un archivo NUEVO. No modifica el combate, ni el randomizador, ni el
#     editor de la aventura. Reutiliza lo que ya existe:
#       * Connection / Parser / RecordWriter  (001_Connection_Communication.rb)
#       * CableClub::get_server_info           (002_CableClub.rb) — host de serverinfo.ini
#       * AnilOnlineEV.apply_to_party/restore_party (010) — EVs online NO destructivos
#       * pbAnilEVEditor (010), Spriteset_Map.viewport (motor), Sprite_Character
#   - La entrada a la plaza aplica los MISMOS EVs/IVs/PP que el online normal al
#     entrar y los RESTAURA al salir (mismo ciclo que pbAnilStartOnline).
#   - Los combates dentro de la plaza fijan el ajuste a NIVEL 50 y son NO
#     destructivos (el Cable Club ya restaura niveles/objetos/PS en su `ensure`).
#
#  Mapa del hub: Map 220 ("Plaza Online"), aparición en (16,15).
#===============================================================================

module AnilHub
  HUB_MAP_ID   = 220        # Mapa "Plaza Online" (creado en la copia ONLINE)
  SPAWN_X      = 16
  SPAWN_Y      = 15
  HUB_PORT     = 25566      # Servicio de posiciones/chat/retos (independiente del 25565)
  MAX_CHAT     = 100        # Largo máximo del chat (el server también lo recorta)
  PING_EVERY   = 10.0       # s: manda "ping" si no hubo tráfico (heartbeat < 30s del server)

  # true SOLO mientras hay una sesión de plaza viva (para la red de seguridad anti-atasco).
  @session_active = false
  class << self; attr_accessor :session_active; end
  CHAT_LINES   = 6          # líneas visibles en el overlay de chat

  module_function

  # --- Modo del jugador (para el shard). Igual criterio que el resto del online. ----
  def player_mode
    running = false
    begin
      running = (defined?(ChallengeModes) && ChallengeModes.running?)
    rescue
      running = false
    end
    return "normal" unless running
    randomized = false
    begin
      randomized = (defined?(RandomizedChallenge) && RandomizedChallenge.enabled?)
    rescue
      randomized = false
    end
    return "randomlocke" if randomized
    "nuzlocke"
  end

  def mode_label(m)
    case m
    when "normal"      then _INTL("Normal")
    when "nuzlocke"    then _INTL("Nuzlocke")
    when "randomlocke" then _INTL("Randomlocke")
    else m.to_s
    end
  end

  # Log de diagnóstico de la plaza (se escribe en la carpeta del juego).
  def log(msg)
    File.open("anil_hub_debug.txt", "a") { |f| f.puts("#{Time.now.strftime('%H:%M:%S')}  #{msg}") }
  rescue
  end

  # Nombre seguro para MOSTRAR (nombres se muestran vía pbMessage en los retos, que
  # interpreta códigos como \v[]/\c[]). Quita la '\' y caracteres de control. Defensa
  # en profundidad por si el server fuese uno malicioso (el oficial ya lo sanea).
  def safe_name(s)
    s.to_s.gsub("\\", "").gsub(/[[:cntrl:]]/, "")[0, 24]
  end
end

#===============================================================================
# Personaje "fantasma" de otro jugador. Solo guarda posición/gráfico para que un
# Sprite_Character lo dibuje alineado con la cámara. NUNCA llamamos a su #update
# (evita cualquier lógica de pasos/encuentros): movemos con moveto (snap).
#===============================================================================
class AnilHubChar < Game_Character
  def initialize
    super(nil)
    @through     = true
    @walk_anime  = true
    @move_speed  = 4
    @net_target  = nil
    moveto(AnilHub::SPAWN_X, AnilHub::SPAWN_Y)
  end

  def set_graphic(name)
    # El charset llega de la red y se usa como nombre de archivo (Graphics/Characters/<x>);
    # filtramos a caracteres seguros para no intentar rutas raras (defensa en profundidad).
    @character_name = name.to_s.gsub(/[^A-Za-z0-9_\- ]/, "")
    @character_hue  = 0
  end

  # Snap inmediato (para el spawn inicial).
  def place(nx, ny, ndir)
    moveto(nx, ny)
    @direction = ndir if [2, 4, 6, 8].include?(ndir)
  end

  # Recibe el destino de red. Guarda velocidad para animar/interpolar al mismo ritmo
  # que el otro cliente (caminar/correr/bici) y deja el destino pendiente.
  def apply_target(nx, ny, ndir, speed)
    self.move_speed = speed if speed && speed >= 1 && speed <= 6
    @net_target = [nx, ny, ndir]
  end

  # Se llama cada frame: interpola/anima y, cuando termina el paso actual, avanza
  # hacia el destino de red. ENCADENA pasos hasta alcanzarlo (movimiento continuo,
  # sin frenar entre casillas) y hace snap solo si el objetivo quedó muy lejos (lag).
  def net_tick
    update   # Game_Character#update: interpola posición y anima el patrón de pasos
    return unless @net_target
    return if moving?
    nx, ny, ndir = @net_target
    dx = nx - @x; dy = ny - @y
    if dx == 0 && dy == 0
      @direction = ndir if [2, 4, 6, 8].include?(ndir)
      @net_target = nil
      straighten          # deja el sprite en pose de "parado" (no a media zancada)
    elsif (dx == 0 || dy == 0) && (dx.abs + dy.abs) <= 3
      # Un paso hacia el objetivo; NO limpiamos @net_target: seguimos caminando
      # frame a frame hasta llegar (así alcanza suave si venía atrasado).
      move_right if dx > 0
      move_left  if dx < 0
      move_down  if dy > 0
      move_up    if dy < 0
    else
      moveto(nx, ny)      # demasiado lejos (lag/teleport): ajusta de golpe
      @direction = ndir if [2, 4, 6, 8].include?(ndir)
      @net_target = nil
      straighten
    end
  rescue
    @net_target = nil    # ante cualquier fallo, descarta el destino y sigue
  end

  # IMPRESCINDIBLE: varios plugins (sombras, reflejos) llaman a `name` sobre el
  # personaje. Game_Character base NO define `name` (solo Game_Event), y sin esto
  # crasheaba al crear el sprite del peer y sacaba a todos de la plaza.
  def name; ""; end

  # map por defecto = $game_map (ya lo da Game_Character#map). No hace falta nada más.
end

#===============================================================================
# Menú gráfico de la Plaza (estilo Añil): panel azul/oro centrado, selector del
# DP Pause Menu, iconos para las opciones que los tienen y texto para el resto.
# Cada opción es [etiqueta, icono_base | nil] (usa "<base>A" de DP Pause Menu).
# #run devuelve el índice elegido, o -1 si se cancela (BACK).
#===============================================================================
class AnilHubMenu
  ICONDIR = "Graphics/Pictures/DP Pause Menu/"
  ROWH    = 44
  HEADH   = 34
  PANELW  = 224
  BOX     = 32   # tamaño del icono en el menú

  def initialize(options, title)
    @options = options
    @title   = title
    @index   = 0
    @count   = @options.length
    @vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @vp.z = 99999
    @h  = HEADH + @count * ROWH + 8
    @x0 = (Graphics.width - PANELW) / 2
    @y0 = (Graphics.height - @h) / 2
    @txoff = 12 + BOX + 8   # dónde empieza el texto (tras el icono)
    @icons = []
    build_panel
    build_icons             # crea @icons ANTES del selector (reposition_selector usa refresh_icons)
    build_selector
    refresh_icons
  end

  # Panel de fondo + borde + título + etiquetas de texto (los iconos van aparte).
  def build_panel
    @bg = Sprite.new(@vp); @bg.z = 0
    b = Bitmap.new(PANELW, @h)
    b.fill_rect(0, 0, PANELW, @h, Color.new(20, 40, 78, 235))
    gold = Color.new(240, 208, 96)
    b.fill_rect(0, 0, PANELW, 2, gold)
    b.fill_rect(0, @h - 2, PANELW, 2, gold)
    b.fill_rect(0, 0, 2, @h, gold)
    b.fill_rect(PANELW - 2, 0, 2, @h, gold)
    b.fill_rect(0, HEADH - 2, PANELW, 2, gold)
    pbSetSystemFont(b)
    pbDrawShadowText(b, 0, 4, PANELW, 26, @title, Color.new(255, 236, 168), Color.new(0, 0, 0), 1)
    @options.each_with_index do |opt, i|
      ry = HEADH + i * ROWH
      pbDrawShadowText(b, @txoff, ry + (ROWH - 28) / 2, PANELW - @txoff - 8, 28, opt[0],
                       Color.new(255, 255, 255), Color.new(0, 0, 0))
    end
    @bg.bitmap = b
    @bg.x = @x0
    @bg.y = @y0
  end

  # Ruta del icono a COLOR: ítem (Symbol) => icono del ítem; DP (String) => "<base>B"
  # (versión a color, con género si aplica), con respaldo a "<base>A".
  def icon_path(icon)
    return nil unless icon
    if icon.is_a?(Symbol)
      return (GameData::Item.icon_filename(icon) rescue nil)
    end
    g = ($player.gender == 1 ? "f" : "m")
    [ICONDIR + icon + "B", ICONDIR + icon + "B" + g, ICONDIR + icon + "A"].each do |p|
      return p if (pbResolveBitmap(p) rescue nil)
    end
    nil
  end

  # Un sprite de icono por fila (para poder colorear/desaturar según selección).
  def build_icons
    @icons = []
    @options.each_with_index do |opt, i|
      spr = nil
      path = icon_path(opt[1])
      if path
        ab = (AnimatedBitmap.new(path) rescue nil)
        if ab && ab.bitmap
          bmp = Bitmap.new(BOX, BOX)
          bmp.stretch_blt(Rect.new(0, 0, BOX, BOX), ab.bitmap,
                          Rect.new(0, 0, ab.bitmap.width, ab.bitmap.height))
          ab.dispose
          spr = Sprite.new(@vp)
          spr.bitmap = bmp
          spr.z = 2
          spr.x = @x0 + 12
          spr.y = @y0 + HEADH + i * ROWH + (ROWH - BOX) / 2
        end
      end
      @icons[i] = spr
    end
  end

  # Color en la opción seleccionada; gris (desaturado) en las demás.
  def refresh_icons
    return unless @icons
    @icons.each_with_index do |spr, i|
      next unless spr
      spr.tone = (i == @index ? Tone.new(0, 0, 0, 0) : Tone.new(0, 0, 0, 255))
    end
  end

  def build_selector
    @sel = Sprite.new(@vp); @sel.z = 1
    ab = (AnimatedBitmap.new(ICONDIR + "selector") rescue nil)
    if ab && ab.bitmap
      @sel.bitmap = ab.bitmap
      @sel.zoom_x = (PANELW - 12).to_f / ab.bitmap.width
      @sel.zoom_y = ROWH.to_f / ab.bitmap.height
    else
      sb = Bitmap.new(PANELW - 12, ROWH)
      sb.fill_rect(0, 0, PANELW - 12, ROWH, Color.new(255, 255, 255, 60))
      @sel.bitmap = sb
    end
    @sel.x = @x0 + 6
    reposition_selector
  end

  def reposition_selector
    @sel.y = @y0 + HEADH + @index * ROWH
    refresh_icons
  end

  def run
    ret = -1
    loop do
      Graphics.update
      Input.update
      pbUpdateSceneMap
      if Input.trigger?(Input::DOWN)
        pbPlayCursorSE; @index = (@index + 1) % @count; reposition_selector
      elsif Input.trigger?(Input::UP)
        pbPlayCursorSE; @index = (@index - 1) % @count; reposition_selector
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE; ret = @index; break
      elsif Input.trigger?(Input::BACK)
        pbPlayCancelSE; ret = -1; break
      end
    end
    ret
  end

  def dispose
    @bg.bitmap.dispose if @bg && @bg.bitmap && !@bg.bitmap.disposed?
    @bg.dispose if @bg && !@bg.disposed?
    @sel.dispose if @sel && !@sel.disposed?
    (@icons || []).each do |spr|
      next unless spr
      spr.bitmap.dispose if spr.bitmap && !spr.bitmap.disposed?
      spr.dispose unless spr.disposed?
    end
    @vp.dispose if @vp && !@vp.disposed?
  end
end

#===============================================================================
# Overlay de chat: caja compacta abajo-izquierda, se ajusta al nº de líneas y se
# AUTO-OCULTA a los pocos segundos (no tapa la pantalla). Llamar #update cada frame.
#===============================================================================
class AnilHubChatOverlay
  MAXLINES = 5
  TTL      = 12.0   # segundos que una línea permanece visible
  LH       = 22     # alto por línea
  WIDTH    = 320

  def initialize(viewport)
    @sprite = Sprite.new(viewport)
    @sprite.z = 90000
    @sprite.visible = false
    @lines = []      # [texto, tiempo]
    @dirty = false
  end

  def push(line)
    @lines.push([line.to_s, Time.now.to_f])
    @lines.shift while @lines.length > MAXLINES
    @dirty = true
  end

  # Se llama cada frame: caduca líneas viejas y redibuja si hace falta.
  def update
    now = Time.now.to_f
    n = @lines.length
    @lines.reject! { |l| now - l[1] > TTL }
    @dirty = true if @lines.length != n
    rebuild if @dirty
  end

  def rebuild
    @dirty = false
    @sprite.bitmap.dispose if @sprite.bitmap && !@sprite.bitmap.disposed?
    if @lines.empty?
      @sprite.bitmap = nil
      @sprite.visible = false
      return
    end
    h = @lines.length * LH + 8
    bmp = Bitmap.new(WIDTH, h)
    bmp.fill_rect(0, 0, WIDTH, h, Color.new(0, 0, 0, 120))
    pbSetSmallFont(bmp) rescue pbSetSystemFont(bmp)
    @lines.each_with_index do |l, i|
      pbDrawShadowText(bmp, 6, 2 + i * LH, WIDTH - 12, LH, l[0],
                       Color.new(255, 255, 255), Color.new(0, 0, 0))
    end
    @sprite.bitmap = bmp
    @sprite.x = 6
    @sprite.y = Graphics.height - h - 8
    @sprite.visible = true
  end

  def dispose
    @sprite.bitmap.dispose if @sprite.bitmap && !@sprite.bitmap.disposed?
    @sprite.dispose unless @sprite.disposed?
  end
end

#===============================================================================
# Sesión de la Plaza Online. Se construye con una Connection ya abierta al 25566.
# Devuelve por #run un código de combate (String) si hay que ir a un combate, o
# nil si el jugador salió de la plaza.
#===============================================================================
class AnilHubSession
  def initialize(connection)
    @conn        = connection
    @connected   = false
    @my_sid      = nil
    @peers       = {}      # sid => { char:, sprite:, label:, name:, pid: }
    @chat        = nil
    @pending_challenge = nil   # [sid, name] de un reto entrante por confirmar
    @match_code  = nil
    @exit        = false
    @disc_reason = nil
    @last_sent   = nil
    @last_tx     = Time.now.to_f
  end

  def viewport
    Spriteset_Map.viewport
  end

  # ---- envío --------------------------------------------------------------
  def send(*fields)
    return unless @conn
    begin
      if @conn.can_send?
        @conn.send do |w|
          fields.each { |f| w.str(f.to_s) }
        end
        @last_tx = Time.now.to_f
      end
    rescue
    end
  end

  def hello
    send("hello", $player.id, $player.name, AnilHub.player_mode,
         ($game_player.character_name rescue ""))
  end

  # ---- lectura ------------------------------------------------------------
  def pump
    # Drena todos los records disponibles este frame (Connection procesa 1 por update).
    loop do
      got = false
      @conn.update do |record|
        got = true
        f = []
        f << record.str until record.empty?   # consume TODO el record (evita ProtocolError)
        dispatch(f)
      end
      break unless got
    end
  rescue Connection::Disconnected => e
    @disc_reason = (e.message rescue "desconectado")
    @exit = true
  rescue => e
    # Cualquier otro error inesperado: log y salir limpio de la plaza.
    AnilHub.log("pump error: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    @disc_reason = "error de red"
    @exit = true
  end

  def dispatch(f)
    return if f.empty?
    case f[0]
    when "welcome"
      @connected = true
      @my_sid = f[1].to_i
    when "spawn"
      add_peer(f[1].to_i, f[2], AnilHub.safe_name(f[3]), f[4], f[5].to_i, f[6].to_i, f[7].to_i)
    when "move"
      # move,<sid>,<x>,<y>,<dir>,<charset>,<speed>
      p = @peers[f[1].to_i]
      if p
        cs = f[5]
        p[:char].set_graphic(cs) if cs && !cs.empty? && cs != p[:char].character_name
        p[:char].apply_target(f[2].to_i, f[3].to_i, f[4].to_i, (f[6] || 4).to_i)
      end
    when "despawn"
      remove_peer(f[1].to_i)
    when "chat"
      # chat,<sid>,<nombre>,<texto>
      @chat.push(sprintf("%s: %s", f[2].to_s, f[3].to_s)) if @chat
    when "challenged"
      @pending_challenge = [f[1].to_i, AnilHub.safe_name(f[2])]
    when "declined"
      @chat.push(_INTL("Rechazaron tu reto.")) if @chat
    when "match"
      @match_code = f[1].to_s
      @exit = true
    when "sys"
      @chat.push(sprintf("* %s", f[1].to_s)) if @chat
    end
  end

  # ---- peers --------------------------------------------------------------
  def add_peer(sid, pid, name, charset, x, y, dir)
    return if sid == @my_sid || @peers[sid]
    ch = AnilHubChar.new
    ch.set_graphic(charset)
    ch.place(x, y, dir)
    spr = Sprite_Character.new(viewport, ch)
    lbl = Sprite.new(viewport)
    lbl.z = 80000
    draw_label(lbl, name)
    @peers[sid] = { char: ch, sprite: spr, label: lbl, name: name, pid: pid }
  rescue => e
    AnilHub.log("add_peer error sid=#{sid}: #{e.class}: #{e.message}\n#{e.backtrace&.first(4)&.join("\n")}")
    spr.dispose if spr && !spr.disposed? rescue nil
    lbl.dispose if lbl && !lbl.disposed? rescue nil
  end

  def remove_peer(sid)
    p = @peers.delete(sid)
    return unless p
    p[:sprite].dispose if p[:sprite] && !p[:sprite].disposed?
    if p[:label]
      p[:label].bitmap.dispose if p[:label].bitmap && !p[:label].bitmap.disposed?
      p[:label].dispose unless p[:label].disposed?
    end
  end

  def draw_label(sprite, name)
    sprite.bitmap.dispose if sprite.bitmap && !sprite.bitmap.disposed?
    b = Bitmap.new(160, 28)
    pbSetSmallFont(b) rescue pbSetSystemFont(b)
    pbDrawShadowText(b, 0, 0, 160, 28, name.to_s, Color.new(255, 255, 255),
                     Color.new(0, 0, 0), 1)  # centrado
    sprite.bitmap = b
    sprite.ox = 80
    sprite.oy = 0
  end

  def update_peer_sprites
    @peers.each_value do |p|
      begin
        p[:char].net_tick        # mueve/anima al peer hacia su destino de red
        p[:sprite].update        # dibuja el sprite ya actualizado
        # etiqueta encima del fantasma
        lbl = p[:label]
        ch  = p[:char]
        lbl.x = ch.screen_x
        lbl.y = ch.screen_y - 52
      rescue => e
        AnilHub.log("update_peer error: #{e.class}: #{e.message}")
      end
    end
  end

  # ---- interacción --------------------------------------------------------
  def front_tile
    x = $game_player.x; y = $game_player.y
    case $game_player.direction
    when 2 then [x, y + 1]
    when 4 then [x - 1, y]
    when 6 then [x + 1, y]
    when 8 then [x, y - 1]
    else        [x, y]
    end
  end

  def peer_in_front
    fx, fy = front_tile
    @peers.each { |sid, p| return [sid, p] if p[:char].x == fx && p[:char].y == fy }
    nil
  end

  # Reto a un jugador que tienes enfrente.
  def try_challenge
    hit = peer_in_front
    unless hit
      return
    end
    sid, p = hit
    cmd = pbMessage(_INTL("¿Retar a {1} a un combate?", p[:name]),
                    [_INTL("Retar"), _INTL("Cancelar")], 2)
    if cmd == 0
      send("challenge", sid)
      pbMessage(_INTL("Reto enviado a {1}. Esperando respuesta...", p[:name]))
    end
  end

  # Confirmación de un reto entrante (se muestra en un punto seguro del bucle).
  def resolve_pending_challenge
    return unless @pending_challenge
    sid, name = @pending_challenge
    @pending_challenge = nil
    # El retador puede haberse ido: solo aceptamos si sigue presente.
    if !@peers[sid]
      return
    end
    if pbConfirmMessage(_INTL("¡{1} te reta a un combate! ¿Aceptar?", name))
      send("accept", sid)
      pbMessage(_INTL("Preparando el combate..."))
    else
      send("decline", sid)
    end
  end

  # Menú de servicios (tecla de menú). Todo NO destructivo.
  # cmdIfCancel = -1 => al pulsar BACK, pbMessage devuelve -1 y solo CERRAMOS el menú
  # (seguimos en la plaza). Salir de la plaza requiere elegirlo y confirmarlo.
  def open_menu
    send("ping")   # evita que el heartbeat del server nos tire mientras el menú está abierto
    loop do
      opts = [[_INTL("Equipo"),               "pokemon"],
              [_INTL("Mochila"),              "bag"],
              [_INTL("Chat"),                 "online"],
              [_INTL("Curar equipo"),         :POTION],
              [_INTL("PC de Pokémon"),        :DUBIOUSDISC],
              [_INTL("Editor de EVs online"), :PROTEIN],
              [_INTL("Salir de la plaza"),    "exit"]]
      cmd = -1
      begin
        menu = AnilHubMenu.new(opts, _INTL("Plaza Online · {1}", AnilHub.mode_label(AnilHub.player_mode)))
        cmd = menu.run
      rescue => e
        AnilHub.log("menu error: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      ensure
        menu.dispose if menu
      end
      return if cmd < 0 || cmd >= opts.length   # BACK / cancelar => cerrar menú (seguir en la plaza)
      # ping antes de los submenús largos: el bucle se bloquea mientras están abiertos
      # y no se manda tráfico; esto reduce el riesgo de que el server nos dé por caídos.
      send("ping")
      case cmd
      when 0 then open_party
      when 1 then open_bag
      when 2 then do_chat
      when 3
        $player.heal_party
        pbMessage(_INTL("Tu equipo está como nuevo."))
      when 4
        (pbPokeCenterPC rescue pbMessage(_INTL("No se pudo abrir el PC aquí.")))
      when 5
        pbAnilEVEditor
        # Si cambió el plan de EVs, reaplícalo en caliente para que valga ya.
        reapply_evs
      when 6
        if pbConfirmMessage(_INTL("¿Salir de la Plaza Online?"))
          @exit = true; return
        end
      end
    end
  end

  # Abre la pantalla de equipo (ver/reordenar/resumen). En la plaza ignoramos los
  # movimientos de campo (no se usan aquí), así que es seguro.
  def open_party
    pbFadeOutIn(99999) do
      sscene  = PokemonParty_Scene.new
      sscreen = PokemonPartyScreen.new(sscene, $player.party)
      sscreen.pbPokemonScreen
    end
  end

  # Abre la mochila (solo para ver/organizar). Ignoramos objetos usados en la plaza.
  def open_bag
    pbFadeOutIn(99999) do
      scene  = PokemonBag_Scene.new
      screen = PokemonBagScreen.new(scene, $bag)
      screen.pbStartScreen
    end
  end

  def do_chat
    txt = anil_hub_chat_input
    return if !txt || txt.strip.empty?
    send("chat", txt.strip)
  end

  # En móvil (mkxp-z/NaviaXP) el IME del teclado virtual duplica/repite teclas
  # ("letras a lo loco"). El teclado EN PANTALLA del juego (textinput != 0) no usa
  # el IME, así que en móvil lo forzamos solo para el chat y restauramos después.
  # En PC se respeta el método de entrada que el jugador tenga configurado.
  def anil_hub_chat_input
    help = _INTL("Chat (máx {1}):", AnilHub::MAX_CHAT)
    is_pc = (RUBY_PLATFORM =~ /mingw|mswin|windows/i)
    return pbEnterText(help, 0, AnilHub::MAX_CHAT) if is_pc
    prev = ($PokemonSystem.textinput rescue nil)
    begin
      ($PokemonSystem.textinput = 1) rescue nil
      pbEnterText(help, 0, AnilHub::MAX_CHAT)
    ensure
      ($PokemonSystem.textinput = prev) rescue nil unless prev.nil?
    end
  end

  # Reaplica el plan de EVs si el jugador lo editó dentro de la plaza. Como los
  # EVs ya se "aplicaron" al entrar (bandera anil_ev_backup puesta), primero
  # restauramos y volvemos a aplicar para que el nuevo plan surta efecto.
  def reapply_evs
    AnilOnlineEV.restore_party
    AnilOnlineEV.apply_to_party
  rescue
  end

  # ---- bucle principal ----------------------------------------------------
  def run
    hello
    @chat = AnilHubChatOverlay.new(viewport)
    begin
      loop do
        Graphics.update
        Input.update
        # Actualiza mapa/jugador SIN usar miniupdate: miniupdate activa
        # $game_temp.in_mini_update, y eso BLOQUEA el movimiento del jugador
        # (Game_Player#update_command_new exige !in_mini_update). Replicamos la
        # actualización necesaria a mano para que sí se pueda caminar.
        map_tick

        pump                    # recibe posiciones/chat/retos
        break if @exit

        send_my_position
        heartbeat
        update_peer_sprites
        @chat.update
        resolve_pending_challenge

        if Input.trigger?(Input::USE)
          try_challenge
        elsif Input.trigger?(Input::ACTION) || Input.trigger?(Input::BACK)
          open_menu
        end
        break if @exit
      end
    ensure
      cleanup
    end
    # Avísale al servidor que salimos (a menos que vayamos directo a un combate;
    # igual conviene liberar el socket del hub durante el combate).
    send("bye")
    return @match_code
  end

  def send_my_position
    charset = ($game_player.character_name rescue "")
    speed   = ($game_player.move_speed rescue 4)
    speed   = speed.round rescue 4
    cur = [$game_player.x, $game_player.y, $game_player.direction, charset, speed]
    return if cur == @last_sent
    @last_sent = cur
    send("pos", cur[0], cur[1], cur[2], cur[3], cur[4])
  end

  # Actualiza el mapa y al jugador SIN activar in_mini_update (para que se pueda
  # caminar). Equivale a lo esencial de miniupdate pero sin bloquear el input.
  def map_tick
    return unless $scene.is_a?(Scene_Map)
    $game_player.update
    $scene.updateMaps
    $game_system.update
    $game_screen.update
    $scene.transfer_player if $game_temp.player_transferring
    $scene.updateSpritesets
  end

  def heartbeat
    now = Time.now.to_f
    send("ping") if now - @last_tx > AnilHub::PING_EVERY
  end

  def connected?; @connected; end
  def disc_reason; @disc_reason; end

  def cleanup
    @peers.keys.each { |sid| remove_peer(sid) }
    @chat.dispose if @chat
    @chat = nil
  end
end

#===============================================================================
# Reutilizar el Cable Club para el combate del reto, SALTANDO el tecleo del
# código (usamos el que repartió el servidor del hub). Reabrimos la clase para
# añadir métodos NUEVOS; no tocamos los existentes.
#===============================================================================
class CableClubScreen
  # En un combate de PLAZA ($anil_hub_battle_only) saltamos el menú de actividad
  # (Combate/Intercambio/…) y vamos DIRECTO a combate. Los intercambios se quedan
  # SOLO en el online normal, para no romper el progreso individual.
  alias __anil_orig_choose_activity choose_activity unless method_defined?(:__anil_orig_choose_activity)
  def choose_activity(connection)
    return __anil_orig_choose_activity(connection) unless $anil_hub_battle_only
    # Un reto de plaza = UN SOLO intento de combate. El Cable Club vuelve a
    # choose_activity tras el combate (o tras cancelar); en esa 2ª entrada avisamos
    # al peer y terminamos, para que el stack se desenrolle y ambos vuelvan a la plaza.
    if @anil_hub_done
      (connection.send { |w| w.str("disconnect"); w.str("peer disconnected") }) rescue nil
      return
    end
    @anil_hub_done = true
    exchange_teams(connection) if restore_original_team
    ($game_switches[ENCENDER_PC_ONLINE] = false) rescue nil
    @battle_settings = nil
    choose_battle_settings(connection)   # deja elegir reglas/nivel, como el Cable Club normal
  end

  # Igual que pbStartScreen, pero conectando directo con un código dado.
  def pbStartScreenWithCode(code)
    @scene.pbStartScene
    pbConnectDisconnectSetup
    ret = pbAttemptConnectionWithCode(code)
    pbConnectDisconnectSetup(true)
    @scene.pbEndScene
    return ret
  end

  # Copia de pbAttemptConnection SIN el bucle de entrada de código.
  def pbAttemptConnectionWithCode(code)
    if $player.party_count == 0
      pbDisplay(_INTL("Lo siento, pero debes tener al menos un Pokémon para combatir."))
      return false
    end
    pbSEPlay("GUI save choice")
    slot = $player.save_slot
    if Game.save(slot)
      pbMessage("\\se[]" + _INTL("{1} guardó la partida.", $player.name) + "\\me[GUI save game]\\wtnp[20]")
    else
      pbMessage("\\se[]" + _INTL("El guardado ha fallado.") + "\\wtnp[30]")
      return false
    end
    connect_setup
    begin
      pbConnectServer(code.to_i)
      raise Connection::Disconnected.new("disconnected")
    rescue Connection::Disconnected => e
      case e.message
      when "disconnected"
        pbDisplay(_INTL("Combate terminado. Volviendo a la plaza..."))
        $game_switches[135] = true
        return true
      when "invalid party"
        pbDisplay(_INTL("Tu equipo contiene Pokémon no permitidos en el Modo Online."))
        return false
      when "peer disconnected"
        pbDisplay(_INTL("El otro Entrenador se ha desconectado."))
        return true
      when "invalid version"
        pbDisplay(_INTL("Tu juego está desactualizado para el Modo Online."))
        return false
      when "connection timed out"
        pbDisplay(_INTL("Error de conexión: tiempo de espera agotado."))
        return false
      else
        pbDisplay(_INTL("El otro Entrenador ya no está disponible."))
        return false
      end
    rescue Errno::ECONNREFUSED
      pbDisplay(_INTL("El Modo Online no está disponible en estos momentos."))
      return false
    rescue
      pbDisplay(_INTL("Ha ocurrido un error inesperado en el combate."))
      return false
    ensure
      pbHideMessageBox
    end
  end
end

# Lanza un combate del hub con el código dado (equivale a pbCableClub pero directo).
# Usa EXACTAMENTE el mismo flujo/reglas que el Cable Club normal (nivel y formato
# se negocian igual que en el online de siempre) y es NO destructivo: el Cable Club
# restaura niveles/objetos/PS en su `ensure`, así que el progreso NUNCA se altera.
def pbAnilHubBattle(code)
  return false if !code
  $anil_hub_battle_only = true   # en la plaza: SOLO combate (sin menú de intercambios)
  begin
    scene  = CableClub_Scene.new
    screen = CableClubScreen.new(scene)
    screen.pbStartScreenWithCode(code)
  ensure
    $anil_hub_battle_only = false
  end
  return true
end

#===============================================================================
# Entrada a la Plaza. Mismo ciclo de vida que pbAnilStartOnline: aplica EVs/IVs/PP
# al entrar y los RESTAURA al salir; guarda posición de retorno; turbo OFF.
#===============================================================================
def pbAnilStartHub
  # Explicación breve de qué es la Plaza Online.
  pbMessage(_INTL("La Plaza Online es un punto de encuentro con otros jugadores de tu MISMO modo de juego (normal, nuzlocke o randomlocke)."))
  pbMessage(_INTL("Ahí puedes verlos moverse, chatear y retarlos a combates. Los intercambios siguen siendo por el sistema online de siempre (apalabrados)."))
  pbMessage(_INTL("Durante la plaza y sus combates se te aplican tus EVs elegidos e IVs 31; al salir, tus Pokémon recuperan sus estadísticas normales."))
  if !pbConfirmMessage(_INTL("¿Entrar a la Plaza Online?"))
    return
  end
  if $player.party_count == 0
    pbMessage(_INTL("Necesitas al menos un Pokémon para entrar a la plaza."))
    return
  end

  # Neutraliza modos locales que cambian el formato (como en pbAnilStartOnline).
  saved_modes = {}
  [["MODO_VGC", 147], ["MODO_INVERSO", nil], ["MODO_SIN_GRINDEO", nil]].each do |name, fallback|
    sw = (Object.const_defined?(name) ? Object.const_get(name) : fallback)
    next unless sw && $game_switches
    saved_modes[sw] = $game_switches[sw]
    $game_switches[sw] = false
  end
  saved_gamespeed = $GameSpeed rescue 0
  $anil_online_return = [$game_map.map_id, $game_player.x, $game_player.y, $game_player.direction] rescue nil

  host, _port = CableClub.get_server_info
  hub_port = AnilHub::HUB_PORT

  begin
    AnilHub.session_active = true   # ANTES del warp: evita que la red anti-atasco nos saque
    AnilOnlineEV.online_active = true
    $GameSpeed  = 0 rescue nil
    $CanToggle  = false rescue nil
    AnilOnlineEV.apply_to_party
    $player.connecting_online = true

    # Entra al mapa de la plaza.
    pbAnilWarpTo(AnilHub::HUB_MAP_ID, AnilHub::SPAWN_X, AnilHub::SPAWN_Y, 2)
    # Oculta el Pokémon que te sigue mientras estás en la plaza (como el online normal).
    FollowingPkmn.toggle_off rescue nil

    # Bucle de sesiones: cada combate cierra el socket del hub (para no chocar con
    # el heartbeat de 30s) y al volver se reconecta a la plaza.
    loop do
      code = nil
      not_connected = true      # si el bloque no llega a conectar, queda en true
      Connection.open(host, hub_port) do |conn|
        session = AnilHubSession.new(conn)
        code = session.run
        not_connected = !session.connected?
        conn.dispose rescue nil
      end
      if not_connected && code.nil?
        pbMessage(_INTL("No se pudo conectar a la Plaza Online. Revisa tu conexión."))
        break
      end
      break if code.nil?          # el jugador salió de la plaza
      # Hay reto emparejado -> combate por Cable Club, luego volvemos a la plaza.
      pbAnilHubBattle(code)
      # Tras el combate seguimos en la plaza (mismo mapa). Reentra al bucle -> reconecta.
      # Nos aseguramos de estar en la plaza (por si el combate cambió algo).
      if $game_map.map_id != AnilHub::HUB_MAP_ID
        pbAnilWarpTo(AnilHub::HUB_MAP_ID, AnilHub::SPAWN_X, AnilHub::SPAWN_Y, 2)
      end
      # El combate reactiva el follower (pbConnectDisconnectSetup): vuélvelo a ocultar.
      FollowingPkmn.toggle_off rescue nil
    end

  ensure
    AnilHub.session_active = false
    $player.connecting_online = false
    AnilOnlineEV.restore_party
    saved_modes.each { |sw, val| $game_switches[sw] = val }
    AnilOnlineEV.online_active = false
    FollowingPkmn.toggle_on rescue nil   # restaura el Pokémon que te sigue
    # Volver a donde estábamos antes de entrar a la plaza.
    ret = $anil_online_return
    if ret && ret[0]
      pbAnilWarpTo(ret[0], ret[1], ret[2], ret[3] || 2)
    end
    $anil_online_return = nil
    $GameSpeed = (saved_gamespeed || 0) rescue nil
    ($CanToggle = ($PokemonSystem.only_speedup_battles == 0)) rescue nil
  end
  pbMessage(_INTL("Saliste de la Plaza Online. Tus Pokémon recuperaron sus estadísticas."))
end

# Warp con fundido reutilizando el mecanismo estándar del juego.
def pbAnilWarpTo(map_id, x, y, dir = 2)
  pbFadeOutIn(99999) {
    $game_temp.player_new_map_id    = map_id
    $game_temp.player_new_x         = x
    $game_temp.player_new_y         = y
    $game_temp.player_new_direction = dir
    pbDismountBike rescue nil
    $scene.transfer_player
    $game_map.autoplay
    $game_map.refresh
  }
end

#===============================================================================
# RED DE SEGURIDAD ANTI-ATASCO: si apareces en el mapa de la plaza SIN una sesión
# viva (cierre/crash o un guardado que quedó ahí), te saca automáticamente a tu
# último Centro Pokémon. Va en on_frame_update (NO on_enter_map) porque este último
# NO se dispara al CARGAR/continuar partida — y ahí es justo cuando quedas atrapado.
# El mapa de la plaza no tiene salidas, así que sin esto quedarías encerrado.
#===============================================================================
EventHandlers.add(:on_frame_update, :anil_hub_unstuck, proc {
  next if AnilHub.session_active
  next unless $scene.is_a?(Scene_Map)
  next unless $game_map && $game_map.map_id == AnilHub::HUB_MAP_ID
  next if $game_player && $game_player.moving?
  begin
    dest = nil
    if $anil_online_return && $anil_online_return[0] && $anil_online_return[0] != AnilHub::HUB_MAP_ID
      dest = $anil_online_return
    elsif $PokemonGlobal && $PokemonGlobal.healingSpot
      hs = $PokemonGlobal.healingSpot
      dest = [hs[0], hs[1], hs[2], 2]
    end
    if !dest
      home = (GameData::Metadata.get&.home rescue nil)   # [map, x, y, dir] de inicio
      dest = [home[0], home[1], home[2], home[3] || 2] if home && home[0]
    end
    next unless dest && dest[0]   # sin destino seguro: no arriesgamos un warp inválido
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
    FollowingPkmn.toggle_on rescue nil
  rescue => e
    AnilHub.log("unstuck error: #{e.class}: #{e.message}")
  end
})

#===============================================================================
# Entrada a la Plaza desde el menú de pausa.
#  Este build usa el "DP Pause Menu" (Marin), que arma su PROPIA lista de opciones
#  con iconos custom e IGNORA los MenuHandlers(:pause_menu). Por eso la opción
#  "Plaza" se añade directamente en `Plugins/DP Pause Menu/Script.rb` (junto al
#  botón "Online"), y desde ahí se llama a `pbAnilStartHub` con el menú YA cerrado
#  (sobre el mapa vivo, sin el pbFadeOutIn que dejaría la plaza en negro).
#===============================================================================
