#==============================================================================#
#                         Diamond/Pearl Pause Menu                             #
#                                  by Marin                                    #
#==============================================================================#
#                                Instructions                                  #
#                                                                              #
#  To call the Pause menu individually (not by pressing B), use `pbPauseMenu`  #
#                                                                              #
# To make/add your own options, find `@options = []`. Underneath, all options  #
#        are initialized and added. They follow a very simple format:          #
#           [displayname, unselected, selected, code, (condition)]             #
# `displayname` : This is what's actually displayed on screen.                 #
# `unselected` : This is the icon that will be displayed when the option is    #
#                NOT selected. For it to be gender dependent, make it an array #
# `selected` : This is the icon that will be displayed when the option IS      #
#              selected. For it to be gender dependent, make it an array.      #
# `code` : This is what's executed when you click the button.                  #
# `condition` : If you only want the option to be visible at certain times,    #
#               this is where you can add a condition (e.g. $player.pokedex). #
#==============================================================================#
#                    Please give credit when using this.                       #
#==============================================================================#

# Calls the Pause menu
def pbPauseMenu
  DP_PauseMenu.new
end

# This overwrites the old pause menu. Take/comment out these 10 lines to keep
# the old Pause menu.
class Scene_Map
  def call_menu
    $game_temp.menu_calling = false
    $game_temp.in_menu = true
    $game_player.straighten
    $game_map.update
    pbPauseMenu # Calls the DP Pause Menu
    $game_temp.in_menu = false
  end
end

# Variables used to store last selected index.
class PokemonGlobalMetadata
  attr_accessor :last_menu_index
end

class DP_PauseMenu
  # Color base del texto mostrado
  BaseColor = Color.new(250, 250, 250)
  # Color de sombra del texto mostrado
  ShadowColor = Color.new(75,75,75)
  
  def initialize
    @options = []
    # BOTÓN DE POKÉDEX
    @options << ["Pokédex", "pokedexA", "pokedexB", proc {
      if Settings::USE_CURRENT_REGION_DEX
        pbFadeOutIn do
          scene = PokemonPokedex_Scene.new
          screen = PokemonPokedexScreen.new(scene)
          screen.pbStartScreen
        end
      elsif $player.pokedex.accessible_dexes.length == 1
        $PokemonGlobal.pokedexDex = $player.pokedex.accessible_dexes[0]
        pbFadeOutIn do
          scene = PokemonPokedex_Scene.new
          screen = PokemonPokedexScreen.new(scene)
          screen.pbStartScreen
        end
      else
        pbFadeOutIn do
          scene = PokemonPokedexMenu_Scene.new
          screen = PokemonPokedexMenuScreen.new(scene)
          screen.pbStartScreen
        end
      end 
    }] if $player.has_pokedex
    # BOTÓN DE EQUIPO
    @options << ["Pokémon", "pokemonA", "pokemonB", proc {
      hiddenmove = nil
      pbFadeOutIn(99999) do
        sscene = PokemonParty_Scene.new
        sscreen = PokemonPartyScreen.new(sscene, $player.party)
        hiddenmove = sscreen.pbPokemonScreen
        if hiddenmove
          @sprites.visible = false
          @done = true
        end
      end
      if hiddenmove
        $game_temp.in_menu = false
        pbUseHiddenMove(hiddenmove[0],hiddenmove[1])
      end
      }] if $player.party.size > 0
    # BOTÓN DE MOCHILA
    @options << ["Bolsa", "bagA", ["bagBm", "bagBf"], proc {
      item = nil
      pbFadeOutIn(99999) do
        scene = PokemonBag_Scene.new
        screen = PokemonBagScreen.new(scene, $bag)
        item = screen.pbStartScreen
      end
      next false if !item
      @sprites.visible = false
      @done = true
      $game_temp.in_menu = false
      pbUseKeyItemInField(item)
      next true
    }]
    # BOTÓN DE TARJETA ENTRENADOR
    @options << [$player.name, "PlayercardA", "PlayercardB", proc {
      pbFadeOutIn(99999) do
        scene = PokemonTrainerCard_Scene.new
        screen = PokemonTrainerCardScreen.new(scene)
        screen.pbStartScreen
      end
    }]
    # BOTÓN DE GUARDAR
    @options << ["Guardar", "saveA", ["saveBm","saveBf"], proc {
      @sprites.visible = false
      scene = PokemonSave_Scene.new
      screen = PokemonSaveScreen.new(scene)
      if screen.pbSaveScreen
        @done = true
      else
        @sprites.visible = true
      end
    }]
    # BOTÓN DE OPCIONES
    @options << ["Opciones", "optionsA", "optionsB", proc {
      pbFadeOutIn(99999) do
        scene = PokemonOption_Scene.new
        screen = PokemonOptionScreen.new(scene)
        screen.pbStartScreen
        pbUpdateSceneMap
      end
    }]
    # BOTÓN CAPTURAS POR ZONA (Añil) — qué capturas te faltan. Solo si hay regla de captura.
    if defined?(pbAnilShowCaptureStatus) && defined?(ChallengeModes) &&
       (ChallengeModes.on?(:CAPTURE_COUNTER) || ChallengeModes.on?(:ONE_CAPTURE) || ChallengeModes.on?(:FIRST_CAPTURE))
      @options << ["Capturas", "captureA", "captureB", proc {
        @done = true
        @sprites.visible = false
        @anil_show_captures = true
      }]
    end
    # BOTÓN DE COMBATE ONLINE (Añil) — acceso desde cualquier lugar / Centro Pokémon
    # Importante: NO se corre dentro de pbFadeOutIn (dejaría el mapa en negro durante toda
    # la sesión y el combate). En su lugar cerramos el menú y lanzamos el online sobre el
    # mapa vivo, igual que el Cable Club por NPC (ver más abajo, tras dispose).
    @options << ["Online", "onlineA", "onlineB", proc {
      @done = true
      @sprites.visible = false
      @anil_run_online = true
    }] if defined?(pbAnilOnlineMenu)
    # BOTÓN DE SALIR
    @options << ["Salir", "exitA", "exitB", proc {
      if pbConfirmMessage(_INTL("¿Estás segur\\@ de que quieres volver a la pantalla de título?"))
        @done = true
        @sprites.visible = false
        $game_temp.in_menu = false
        scene = PokemonSave_Scene.new
        screen = PokemonSaveScreen.new(scene)
        screen.pbSaveScreen(true)
        pbFadeOutIn(99999) do
          $scene.dispose
          SaveData.mark_values_as_unloaded
          pbBGMFade(1.0)
          pbBGSFade(1.0)
          $scene = pbCallTitle
        end
      end
    }]
    @count = @options.size
    return if @count == 0
    # Espaciado por opción: 48 normal, pero se reduce si hay tantas opciones que no caben
    # en pantalla (evita desborde y deja hueco abajo para el texto "[F1] Controles").
    @spc = [48, (Graphics.height - 24 - 44) / @count].min
    $PokemonGlobal.last_menu_index ||= 0
    @option = $PokemonGlobal.last_menu_index
    @option = 0 if @option >= @options.size
    @done = false
    @i = 0
    @scaling = 0
    @viewport = Viewport.new(Graphics.width - 204, 4, 200, 24 + @spc * @count)
    @viewport2 = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @viewport2.z = 99999
    @sprites = SpriteHash.new
    @sprites[:bgTop] = Sprite.new(@viewport)
    @sprites[:bgTop].bmp("Graphics/Pictures/DP Pause Menu/bgTop")
    @sprites[:bgMid] = Sprite.new(@viewport)
    @sprites[:bgMid].bmp("Graphics/Pictures/DP Pause Menu/bgMid")
    @sprites[:bgMid].y = 12
    @sprites[:bgMid].zoom_y = @spc * @count
    @sprites[:bgBtm] = Sprite.new(@viewport)
    @sprites[:bgBtm].bmp("Graphics/Pictures/DP Pause Menu/bgBtm")
    @sprites[:bgBtm].y = 12 + @sprites[:bgMid].zoom_y
    @sprites[:sel] = Sprite.new(@viewport)
    @sprites[:sel].bmp("Graphics/Pictures/DP Pause Menu/selector")
    # Selector escalado a la fila y CENTRADO en el icono (evita que invada filas vecinas).
    sel_src_h = (@sprites[:sel].bitmap ? @sprites[:sel].bitmap.height : 52)
    @sel_h = @spc + 4                                   # altura visible (con borde), como el diseño original
    @sprites[:sel].zoom_y = @sel_h.to_f / sel_src_h
    @sprites[:sel].xyz = 8, (36 + @spc * @option - @sel_h / 2), 1
    @sprites[:txt] = TextSprite.new(@viewport)
    # Reset shortcut positioning before drawing any shortcuts
    reset_shortcut_positioning
    draw_fly_shortcut if $bag.has?(:POKERIDER) && ADD_POKERIDER_SHORTCUT_IN_MENU
    draw_vial_shortcut if $bag.has?(:VIAL) || $bag.has?(:EMPTYVIAL)
    draw_radar_shortcut if $bag.has?(:RADAR) && (!RandomizedChallenge.enabled? || RandomizedChallenge.consistent_wild_encounters?)
    draw_repel_shortcut if $bag.has?(:INFREPEL) || $bag.has?(:INFREPELOFF)
    draw_helpful_text
    
    draw_sun_moon_icon
    draw_captured_icon 
    
    for i in 0...@options.size
      @sprites[:txt].draw([
          @options[i][0],72,26 + @spc * i,0,BaseColor,ShadowColor
      ])
      @sprites[@options[i][0].to_sym] = Sprite.new(@viewport)
      idx = (i == @option ? 2 : 1)
      path = @options[i][idx]
      path = path[$player.gender] if path.is_a?(Array)
      @sprites[@options[i][0].to_sym].bmp("Graphics/Pictures/DP Pause Menu/#{path}")
      @sprites[@options[i][0].to_sym].center_origins
      @sprites[@options[i][0].to_sym].xyz = 39, 36 + @spc * i
    end
    pbSEPlay("Voltorb Flip point")
    main
  end
  
  def main
    loop do
      update
      old = @option
      if Input.repeat?(Input::DOWN)
        @option += 1
        @option = 0 if @option == @count
        changed = true
      end
      if Input.repeat?(Input::UP)
        @option -= 1
        @option = @count - 1 if @option == -1
        changed = true
      end
      if $mouse
        for i in 0...@count
          if i != @option && $mouse.inArea?(316,14 + @spc * i,184,@spc)
            @option = i
            changed = true
          end
        end
      end
      if Input.trigger?(Input::JUMPDOWN) && $bag.has?(:POKERIDER) && ADD_POKERIDER_SHORTCUT_IN_MENU
        pbPlayDecisionSE
        if pokerider
          @sprites.visible = false
          @done = true
          pokerider_fly
          ret = -2
          break
        end
      elsif Input.trigger?(Input::JUMPUP) && ( $bag.has?(:VIAL) || $bag.has?(:EMPTYVIAL) )
        pbPlayDecisionSE
        if use_pokevial
          draw_vial_shortcut(true)
        end
      elsif Input.trigger?(Input::AUX2) && ( $bag.has?(:INFREPEL) || $bag.has?(:INFREPELOFF) )
        pbPlayDecisionSE
        pbToggleInfiniteRepel
        draw_repel_shortcut(true)
      elsif Input.trigger?(Input::SPECIAL) && $bag.has?(:RADAR) && (!RandomizedChallenge.enabled? || RandomizedChallenge.consistent_wild_encounters?)
        pbPlayDecisionSE
        pbStartRadar
      end
      confirmed = ($mouse && $mouse.x >= 316 && $mouse.x <= 500 && $mouse.y >= 14 && $mouse.y <= 14 + @spc * @count && $mouse.click?)
      confirmed = true if Input.trigger?(Input::USE)
      if changed
        pbSEPlay("Voltorb Flip mark")
        $PokemonGlobal.last_menu_index = @option
        path = @options[old][1]
        path = path[$player.gender] if path.is_a?(Array)
        @sprites[@options[old][0].to_sym].bmp("Graphics/Pictures/DP Pause Menu/#{path}")
        @sprites[@options[old][0].to_sym].angle = 0
        @sprites[@options[old][0].to_sym].zoom_x = 1
        @sprites[@options[old][0].to_sym].zoom_y = 1
        @sprites[:sel].y = 36 + @spc * @option - (@sel_h || (@spc + 4)) / 2
        path = @options[@option][2]
        path = path[$player.gender] if path.is_a?(Array)
        @sprites[@options[@option][0].to_sym].bmp("Graphics/Pictures/DP Pause Menu/#{path}")
        changed = false
        @scaling = 0
        @sprites[@options[@option][0].to_sym].angle = 0
        @i = 0
      end
      if confirmed
        pbPlayDecisionSE
        @options[@option][3].call
        Input.update
      end
      confirmed = false
      if @done
        break
      elsif Input.trigger?(Input::BACK)
        pbPlayCancelSE
        break
      end
    end
    dispose
    # Online del Añil: se ejecuta con el menú YA cerrado, sobre el mapa visible (sin fundido),
    # para que el mapa no quede en negro durante el matchmaking y el combate.
    if @anil_run_online
      @anil_run_online = false
      $game_temp.in_menu = false
      pbAnilOnlineMenu
      pbUpdateSceneMap
    end
    if @anil_show_captures
      @anil_show_captures = false
      $game_temp.in_menu = false
      # Submenú: elegir entre ver capturas por zona o ver los Pokémon entregados.
      if defined?(pbAnilShowGivenAway)
        loop do
          cmd = pbMessage(_INTL("¿Qué quieres ver?"),
                  [_INTL("Capturas por zona"), _INTL("Pokémon entregados"), _INTL("Salir")], -1)
          case cmd
          when 0 then pbAnilShowCaptureStatus
          when 1 then pbAnilShowGivenAway
          else        break
          end
        end
      else
        pbAnilShowCaptureStatus
      end
      pbUpdateSceneMap
    end
  end
  
  def update
    Graphics.update
    Input.update
    pbUpdateSceneMap
    if @scaling
      @scaling += 1
      case @scaling
      when 1..6
        @sprites[@options[@option][0].to_sym].zoom_x += 0.033
        @sprites[@options[@option][0].to_sym].zoom_y += 0.033
      when 12..18
        @sprites[@options[@option][0].to_sym].zoom_x -= 0.033
        @sprites[@options[@option][0].to_sym].zoom_y -= 0.033
      end
      @scaling = nil if @scaling == 18
    else
      @i += 1
      case @i
      when 1..12
        @sprites[@options[@option][0].to_sym].angle -= 0.5
      when 12..24
        @sprites[@options[@option][0].to_sym].angle -= 0.5
      when 25..36
        @sprites[@options[@option][0].to_sym].angle -= 0.5  
      when 37..48
        @sprites[@options[@option][0].to_sym].angle -= 0.5
      when 49..60
        @sprites[@options[@option][0].to_sym].angle += 0.5
      when 61..72
        @sprites[@options[@option][0].to_sym].angle += 0.5
      when 73..84
        @sprites[@options[@option][0].to_sym].angle += 0.5
      when 85..96
        @sprites[@options[@option][0].to_sym].angle += 0.5
      end
      @i = 0 if @i == 96
    end
  end
  def dispose
    @sprites.dispose
    @viewport.dispose
    Input.update
  end
end