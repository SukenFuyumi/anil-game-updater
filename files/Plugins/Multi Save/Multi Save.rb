# Auto Multi Save by http404error
# Traducción por Maryn @cosmic_pipo/@PkmnRadiante(en TW/X)
# For Pokemon Essentials v21.1

# Description:
#   Adds multiple save slots and the abliity to auto-save.
#   Included is code to autosave every 100 overworld steps. Feel free to edit or delete it (it's right at the top).
#   On the Load screen you can use the left and right buttons while "Continue" is selected to cycle through files.
#   When saving, you can quickly save to the same slot you loaded from, or pick another slot.
#   Battle Challenges are NOT supported.

# Customization:
#   I recommend altering your pause menu to quit to the title screen or load screen instead of exiting entirely.
#     -> For instance, just change the menu text to "Quit to Title" and change `$scene = nil` to `$scene = pbCallTitle`.
#     -> You may need to also add a `SaveData.mark_values_as_unloaded` right before setting $scene.
#     -> If you change `screen.pbSaveScreen` to `screen.pbSaveScreen(true)` here, it will also change the UI behavior slightly for clarity.
#   Call Game.auto_save whenever you want.
#     -> Autosaving during an event script will correctly resume event execution when you load the game.
#     -> I haven't investigated if it might be possible to autosave on closing the window with the X or Alt-F4 yet.
#   You can rename the slots to your liking, or change how many there are.
#   In some cases, you might want to remove the option to save to a different slot than the one you loaded from.

# Notes:
#   On the first Load, the old Game.rxdata will be copied to the first slot in MANUAL_SLOTS. It won't have a known save time though.
#   The interface to `Game.save` has been changed.
#   Due to the slots, alters the save backup system in the case of save corruption/crashes - backups will be named Backup000.rxdata and so on.
#   Heavily modifies the SaveData module and Save and Load screens. This may cause incompatibility with some other plugins or custom game code.
#   Not everything here has been tested extensively, only what applies to normal usage of my game. Please let me know if you run into any problems.

# Future development ideas:
#   Unlimited manual slots are now supported with "Partida <number>.rxdata" naming.
#   Letting the user name their slots seems cool.
#   It would be nice if there was a sliding animation for switching files on that load screen. :)
#   It would be nice if the file select arrows used nicer animated graphics, kind of like the Bag.
#   Maybe auto-save slots should act like a queue instead of cycling around. 

# Autosave every 100 steps

#===============================================================================
#
#===============================================================================
module SaveData
  # You can rename these slots or change the amount of them
  # They change the actual save file names though, so it would take some extra work to use the translation system on them.
  AUTO_SLOTS = [
    'Auto 1',
    'Auto 2',
    'Auto 3'
  ]
  
  # For compatibility with games saved without this plugin
  OLD_SAVE_SLOT = 'Game'

  SAVE_DIR = if File.directory?(System.data_directory)
               System.data_directory
             else
              '.'
             end

  
  # Cache for manual slots to avoid repeated directory scans
  @manual_slots_cache = nil
  @manual_slots_cache_time = nil
  
  # Dynamic manual slots - no longer fixed array
  def self.get_manual_slots(force_refresh = false)
    # Cache slots for 1 second to avoid repeated directory scans
    cache_valid = @manual_slots_cache_time && (Time.now - @manual_slots_cache_time) < 1.0
    return @manual_slots_cache.dup if @manual_slots_cache && cache_valid && !force_refresh
    
    slots = []
    # Find all existing Partida files using Dir.entries (more reliable than glob on Windows)
    begin
      Dir.entries(SAVE_DIR).each do |filename|
        next unless filename.end_with?('.rxdata')
        basename = File.basename(filename, '.rxdata')
        if basename.match?(/^Partida \d+$/)
          slots << basename
        end
      end
    rescue => e
      # Fallback to empty array if directory can't be read
      echoln "Error reading save directory: #{e.message}"
      return []
    end
    
    # Sort by number and cache result
    @manual_slots_cache = slots.sort_by { |slot| slot.match(/Partida (\d+)/)[1].to_i }
    @manual_slots_cache_time = Time.now
    @manual_slots_cache.dup
  end
  
  def self.get_next_manual_slot_number
    existing_numbers = get_manual_slots.map { |slot| slot.match(/Partida (\d+)/)[1].to_i }
    return 1 if existing_numbers.empty?
    (1..existing_numbers.max + 1).find { |n| !existing_numbers.include?(n) } || (existing_numbers.max + 1)
  end
  
  def self.get_new_manual_slot
    "Partida #{get_next_manual_slot_number}"
  end


  def self.each_slot
    (AUTO_SLOTS + get_manual_slots).each { |f| yield f }
  end

  def self.get_full_path(file)
    return File.join(SAVE_DIR, "#{file}.rxdata")
  end

  def self.get_backup_file_path
    backup_file = "Backup000"
    while File.file?(self.get_full_path(backup_file))
      backup_file.next!
    end
    return self.get_full_path(backup_file)
  end

  # Given a list of save file names and a file name in it, return the next file after it which exists
  # If no other file exists, will just return the same file again
  def self.get_next_slot(file_list, file)
    old_index = file_list.find_index(file)
    ordered_list = file_list.rotate(old_index + 1)
    ordered_list.each do |f|
      return f if File.file?(self.get_full_path(f))
    end
    # should never reach here since the original file should always exist
    return file
  end
  # See self.get_next_slot
  def self.get_prev_slot(file_list, file)
    return self.get_next_slot(file_list.reverse, file)
  end

  def self.get_save_count
    count = 0
    self.each_slot do |file_slot|
      full_path = self.get_full_path(file_slot)
      count += 1 if File.file?(full_path)
    end
    return count
  end

  # Returns nil if there are no saves
  # Returns the first save if there's a tie for newest
  # Old saves from previous version don't store their saved time, so are treated as very old
  # OPTIMIZED: Only reads file headers instead of full save data
  def self.get_newest_save_slot
    newest_time = Time.at(0) # the Epoch
    newest_slot = nil
    self.each_slot do |file_slot|
      full_path = self.get_full_path(file_slot)
      next if !File.file?(full_path)
      # Only read the timestamp, not the entire save file
      begin
        save_time = self.read_save_timestamp(full_path)
        if save_time > newest_time
          newest_time = save_time
          newest_slot = file_slot
        end
      rescue
        # If we can't read the timestamp, treat as old save
        next
      end
    end
    # Port old save - copy it regardless of validity, delete original after
    # The load screen will handle showing corruption messages if needed
    if newest_slot.nil? && File.file?(self.get_full_path(OLD_SAVE_SLOT))
      old_save_path = self.get_full_path(OLD_SAVE_SLOT)
      first_slot = get_new_manual_slot
      begin
        file_copy(old_save_path, self.get_full_path(first_slot))
        # Delete the old Game.rxdata after porting so it doesn't get copied again
        File.delete(old_save_path) rescue nil
        return first_slot
      rescue
        # Copy failed, don't return the slot
      end
    end
    return newest_slot
  end
  
  # Fast method to read only the timestamp from a save file
  # Returns Time object or Time.at(1) if not available
  def self.read_save_timestamp(file_path)
    File.open(file_path, "rb") do |file|
      save_data = Marshal.load(file)
      return save_data[:player].last_time_saved || Time.at(1)
    end
  rescue
    return Time.at(1)
  end

  # Safe read method with automatic backup and recovery
  # @param file_path [String] full path to save file
  # @return [Hash] save data, or empty hash if failed
  def self.read_from_file_safe(file_path, create_backup: false)
    backup_path = file_path + ".bak"
    
    # Try to load the save file first
    begin
      save_data = self.read_from_file(file_path)
      
      unless self.valid?(save_data)
        raise "Invalid save data"
      end
      
      # Create backup asynchronously in background thread to avoid blocking
      if create_backup && File.file?(file_path)
        Thread.new do
          begin
            file_copy(file_path, backup_path)
          rescue => e
            echoln "Warning: Could not create backup: #{e.message}"
          end
        end
      end
      
      return save_data
    rescue ArgumentError, TypeError, Marshal::RestoreError => e
      # Marshal loading error - file is corrupted
      echoln "Save file corrupted (#{e.class}: #{e.message})"
      
      # If backup exists, try to restore from it
      if File.file?(backup_path)
        begin
          # Try to load the backup first to verify it's valid
          backup_save_data = self.read_from_file(backup_path)
          
          unless self.valid?(backup_save_data)
            raise "Backup is also invalid"
          end
          
          # Backup is valid, replace corrupt file with it
          file_copy(backup_path, file_path)
          echoln "File restored successfully from backup"
          return backup_save_data
        rescue ArgumentError, TypeError, Marshal::RestoreError => backup_error
          # Backup is also corrupted
          echoln "Backup is also corrupted (#{backup_error.class}: #{backup_error.message})"
          return {}
        rescue => backup_error
          # Other error with backup
          echoln "Error loading backup: #{backup_error.message}"
          return {}
        end
      else
        # No backup available
        echoln "No backup available for recovery"
        return {}
      end
    rescue => e
      # Other errors (file not found, permissions, etc.)
      echoln "Error loading save file: #{e.class}: #{e.message}"
      return {}
    end
  end

  # @return [Boolean] whether any save file exists
  def self.exists?
    self.each_slot do |slot|
      full_path = SaveData.get_full_path(slot)
      return true if File.file?(full_path)
    end
    return false
  end

  # This is used in a hidden function (ctrl+down+cancel on title screen) or if the save file is corrupt
  # Pass nil to delete everything, or a file path to just delete that one
  # @raise [Error::ENOENT]
  def self.delete_file(file_path=nil)
    if file_path
      File.delete(file_path) if File.file?(file_path)
    else
      self.each_slot do |slot|
        full_path = self.get_full_path(slot)
        File.delete(full_path) if File.file?(full_path)
      end
    end
  end

  # Runs all possible conversions on the given save data.
  # Saves a backup before running conversions.
  # @param save_data [Hash] save data to run conversions on
  # @return [Boolean] whether conversions were run
  def self.run_conversions(save_data)
    validate save_data => Hash
    conversions_to_run = self.get_conversions(save_data)
    return false if conversions_to_run.none?
    File.open(SaveData.get_backup_file_path, 'wb') { |f| Marshal.dump(save_data, f) }
    Console.echo_h1 "Backed up save to #{SaveData.get_backup_file_path}"
    Console.echo_h1 "Running #{conversions_to_run.length} conversions..."
    conversions_to_run.each do |conversion|
      Console.echo_li "#{conversion.title}..."
      conversion.run(save_data)
      Console.echo_done ' done.'
    end
    echoln '' if conversions_to_run.length > 0
    Console.echo_h2("All save file conversions applied successfully", text: :green)
    save_data[:essentials_version] = Essentials::VERSION
    save_data[:game_version] = Settings::GAME_VERSION
    return true
  end
end

#===============================================================================
#
#===============================================================================
class PokemonLoad_Scene
  def pbChoose(commands, continue_idx)
    @sprites["cmdwindow"].commands = commands
    loop do
      Graphics.update
      Input.update
      pbUpdate
      if Input.trigger?(Input::USE)
        return @sprites["cmdwindow"].index
      elsif @sprites["cmdwindow"].index == continue_idx
        if Input.trigger?(Input::LEFT)
          return -3
        elsif Input.trigger?(Input::RIGHT)
          return -2
        end
      end
    end
  end
end

#===============================================================================
#
#===============================================================================
class PokemonLoadScreen
  def initialize(scene)
    @scene = scene
    @selected_file = $player&.last_save_slot || SaveData.get_newest_save_slot
  end

  # @param file_path [String] file to load save data from
  # @return [Hash] save data
  def load_save_file(file_path)
    save_data = SaveData.read_from_file_safe(file_path, create_backup: false)
    
    # If loading failed and returned empty hash, prompt for deletion
    if save_data.empty? && File.file?(file_path)
      backup_path = file_path + ".bak"
      if File.file?(backup_path)
        pbMessage(_INTL("El archivo de guardado está corrupto. Se restaurará desde el backup.") + "\1")
      else
        pbMessage(_INTL("El archivo de guardado está corrupto y no se ha encontrado ningún backup para este.") + "\1")
        if self.prompt_save_deletion(file_path, skip_first_prompt: true)
          return :deleted
        else
          # User chose not to delete or deletion failed - skip this file
          return :skip
        end
      end
    end
    
    return save_data
  end

  # Called if save file is invalid.
  # Prompts the player to delete the save files.
  # Returns true if file was deleted, false otherwise
  def prompt_save_deletion(file_path, skip_first_prompt: false)
    pbMessage(_INTL("El archivo de guardado está corrupto, o es incompatible con este juego.") + "\1") unless skip_first_prompt
    if pbConfirmMessageSerious(_INTL("¿Quieres eliminar ese archivo guardado?"))
      return self.delete_save_data(file_path)
    end
    return false
  end

  # nil deletes all, otherwise just the given file
  # Returns true if deletion was successful, false otherwise
  def delete_save_data(file_path=nil)
    begin
      SaveData.delete_file(file_path)
      pbMessage(_INTL("El archivo de guardado fue eliminado."))
      return true
    rescue SystemCallError
      pbMessage(_INTL("El archivo de guardado no se pudo eliminar."))
      return false
    end
  end

  def pbStartLoadScreen
    PokeUpdater.check_for_updates() if defined?(PokeUpdater) && defined?(PokeUpdater.check_for_updates) # Required for PokéUpdater to check for gameupdates.
    save_file_list = SaveData::AUTO_SLOTS + SaveData.get_manual_slots
    first_time = true
    
    # OPTIMIZATION: Cache save data to avoid reloading when switching slots
    @save_data_cache = {}
    
    loop do # Outer loop is used for switching save files
      if @selected_file
        # Use cached data if available
        if @save_data_cache[@selected_file]
          @save_data = @save_data_cache[@selected_file]
        else
          @save_data = load_save_file(SaveData.get_full_path(@selected_file))
          # Handle deleted or skipped corrupt save file
          if @save_data == :deleted || @save_data == :skip
            @save_data_cache.delete(@selected_file)
            # Refresh the file list and find next available save (excluding current corrupt file)
            save_file_list = SaveData::AUTO_SLOTS + SaveData.get_manual_slots(true)
            old_selected = @selected_file
            @selected_file = SaveData.get_newest_save_slot
            # If we got the same file again (deletion failed), clear selection to avoid loop
            if @selected_file == old_selected
              @selected_file = nil
            end
            next
          end
          @save_data_cache[@selected_file] = @save_data if !@save_data.empty?
        end
      else
        @save_data = {}
      end
      commands = []
      cmd_continue     = -1
      cmd_new_game     = -1
      cmd_options      = -1
      cmd_language     = -1
      cmd_mystery_gift = -1
      cmd_debug        = -1
      cmd_update       = -1
      cmd_delete       = -1
      cmd_quit         = -1
      show_continue = !@save_data.empty?
      if show_continue
        commands[cmd_continue = commands.length] = "#{@selected_file}"
        if @save_data[:player].mystery_gift_unlocked
          commands[cmd_mystery_gift = commands.length] = _INTL('Regalo Misterioso') # Honestly I have no idea how to make Mystery Gift work well with this.
        end
      end
      commands[cmd_new_game = commands.length]  = _INTL('Partida Nueva')
      commands[cmd_options = commands.length]   = _INTL('Opciones')
      commands[cmd_language = commands.length]  = _INTL('Idioma') if Settings::LANGUAGES.length >= 2
      commands[cmd_debug = commands.length]     = _INTL('Debug') if $DEBUG
      commands[cmd_update = commands.length]    = _INTL('Comprobar Actualizaciones') if defined?(PokeUpdater) && defined?(PokeUpdater.validate_game_version_and_update)
      commands[cmd_delete = commands.length]    = _INTL('Borrar Partida')
      commands[cmd_quit = commands.length]      = _INTL('Cerrar Juego')
      cmd_left = -3
      cmd_right = -2

      map_id = show_continue ? @save_data[:map_factory].map.map_id : 0
      @scene.pbStartScene(commands, show_continue, @save_data[:player], @save_data[:stats], map_id)
      @scene.pbSetParty(@save_data[:player]) if show_continue
      if first_time
        @scene.pbStartScene2
        first_time = false
      else
        @scene.pbUpdate
      end

      loop do # Inner loop is used for going to other menus and back and stuff (vanilla)
        command = @scene.pbChoose(commands, cmd_continue)
        pbPlayDecisionSE if command != cmd_quit

        case command
        when cmd_continue
          @scene.pbEndScene
          Game.load(@save_data)
          $player.last_save_slot = $player.save_slot
          $player.connecting_online = false
          # Create backup asynchronously in background after game has loaded
          Thread.new do
            begin
              backup_path = SaveData.get_full_path(@selected_file) + ".bak"
              file_copy(SaveData.get_full_path(@selected_file), backup_path)
            rescue => e
              echoln "Warning: Could not create backup: #{e.message}"
            end
          end
          return
        when cmd_new_game
          @scene.pbEndScene
          Game.start_new
          return
        when cmd_mystery_gift
          pbFadeOutIn { pbDownloadMysteryGift(@save_data[:player]) }
        when cmd_options
          pbFadeOutIn do
            scene = PokemonOption_Scene.new
            screen = PokemonOptionScreen.new(scene)
            screen.pbStartScreen(true)
          end
        when cmd_language
          @scene.pbEndScene
          $PokemonSystem.language = pbChooseLanguage
          MessageTypes.load_message_files(Settings::LANGUAGES[$PokemonSystem.language][1])
          if show_continue
            @save_data[:pokemon_system] = $PokemonSystem
            File.open(SaveData.get_full_path(@selected_file), "wb") { |file| Marshal.dump(@save_data, file) }
          end
          $scene = pbCallTitle
          return
        when cmd_update
          PokeUpdater.validate_game_version_and_update(true) if defined?(PokeUpdater) && defined?(PokeUpdater.validate_game_version_and_update)
        when cmd_debug
          pbFadeOutIn { pbDebugMenu(false) }
        when cmd_quit
          pbPlayCloseMenuSE
          @scene.pbEndScene
          $scene = nil
          return
        when cmd_delete
          if pbConfirmMessageSerious(_INTL("¿Quieres eliminar este archivo guardado?"))
            self.delete_save_data(SaveData.get_full_path(@selected_file))
            @save_data_cache.delete(@selected_file) # Remove from cache
          end
          @scene.pbCloseScene
          $player&.last_save_slot = nil if $player && $player&.last_save_slot == $player&.save_slot
          @selected_file = SaveData.get_newest_save_slot
          break
        when cmd_left
          @scene.pbCloseScene
          @selected_file = SaveData.get_prev_slot(save_file_list, @selected_file)
          break # to outer loop
        when cmd_right
          @scene.pbCloseScene
          @selected_file = SaveData.get_next_slot(save_file_list, @selected_file)
          break # to outer loop
        else
          pbPlayBuzzerSE
        end
      end
    end
  end
end

#===============================================================================
#
#===============================================================================
class PokemonSave_Scene
  def pbUpdateSlotInfo(slottext)
    pbDisposeSprite(@sprites, "slotinfo")
    @sprites["slotinfo"] = Window_AdvancedTextPokemon.new(slottext)
    @sprites["slotinfo"].viewport = @viewport
    @sprites["slotinfo"].x = 0
    @sprites["slotinfo"].y = 190
    @sprites["slotinfo"].width = 228 if @sprites["slotinfo"].width < 228
    @sprites["slotinfo"].visible = true
  end
  
  def pbClearSlotInfo
    pbDisposeSprite(@sprites, "slotinfo")
  end
end

#===============================================================================
#
#===============================================================================
class PokemonSaveScreen
  def doSave(slot)
    if Game.save(slot)
      pbMessage("\\se[]" + _INTL("{1} guardó la partida.", $player.name) + "\\me[GUI save game]\\wtnp[20]")
      return true
    else
      pbMessage("\\se[]" + _INTL("El guardado ha fallado.") + "\\wtnp[30]")
      return false
    end
  end

  # Return true if pause menu should close after this is done (if the game was saved successfully)
  def pbSaveScreen(exiting=false)
    ret = false
    @scene.pbStartScreen
    if !$player.save_slot
      # New Game - must select slot
      ret = slotSelect(exiting)
    else
      loop do # Add loop to allow returning from slot select
        choices = [
          _INTL("Guardar en #{$player.save_slot}"),
          _INTL("Guardar en otro Archivo"),
          exiting ? _INTL("Salir sin guardar") : _INTL("Cancelar")
        ]
        opt = pbMessage(_INTL("¿Quieres guardar la partida?"), choices, 3)
        if opt == 0
          pbSEPlay("GUI save choice")
          ret = doSave($player.save_slot)
          break
        elsif opt == 1
          pbPlayDecisionSE
          slot_result = slotSelect(exiting)
          if slot_result # If save was successful, exit
            ret = true
            break
          end
          # Clear slot info when returning from slot selection
          @scene.pbClearSlotInfo
          # If slot_result is false, continue loop to return to this menu
        else
          pbPlayCancelSE
          break
        end
      end
    end
    @scene.pbEndScreen
    return ret
  end

  # Call this to open the slot select screen
  # Returns true if the game was saved, otherwise false
  def slotSelect(exiting=false)
    ret = false
    # Build choices: new slot, then all existing slots (except current one)
    choices = []
    choice_info = []
    
    # Add new slot option
    new_slot = SaveData.get_new_manual_slot
    choices << "#{new_slot} (Nuevo)"
    choice_info << _INTL("<ac><c3=D0D0C8,3050C8>(Nuevo Archivo)</c3></ac>")
    
    # Add all existing manual slots (except current one if it exists)
    existing_slots = SaveData.get_manual_slots
    existing_slots.each do |slot|
      next if $player.save_slot == slot  # Skip current slot since it's handled in previous menu
      choices << slot
      choice_info << getSaveInfoBoxContents(slot)
    end
    loop do
      index = slotSelectCommands(choices, choice_info)
      if index >= 0
        selected_choice = choices[index]
        
        # Determine the actual slot name
        if selected_choice.end_with?(" (Nuevo)")
          slot = new_slot
        else
          slot = selected_choice
        end
        
        # Confirm if slot not empty (except for new slot)
        if selected_choice.end_with?(" (Nuevo)") ||
           !File.file?(SaveData.get_full_path(slot)) ||
           pbConfirmMessageSerious(_INTL("¿Estás seguro de sobrescribir en #{slot}?"))
          pbSEPlay('GUI save choice')
          ret = doSave(slot)
        end
      elsif index < 0 # Pressed cancel/back
        if exiting
          next unless pbConfirmMessageSerious(_INTL("¿Estás seguro de salir sin guardar la partida?"))
        else
          # Return false to go back to previous menu
          pbPlayCloseMenuSE
          return false
        end
      end
      break
    end
    pbPlayCloseMenuSE if !ret
    return ret
  end

  # Handles the UI for the save slot select screen. Returns the index of the chosen slot, or -1.
  # Based on pbShowCommands
  def slotSelectCommands(choices, choice_info, defaultCmd=0)
    msgwindow = Window_AdvancedTextPokemon.new(_INTL("¿En qué archivo vas a guardar?"))
    msgwindow.z = 99999
    msgwindow.visible = true
    msgwindow.letterbyletter = true
    msgwindow.back_opacity = MessageConfig::WINDOW_OPACITY
    pbBottomLeftLines(msgwindow, 1)
    $game_temp.message_window_showing = true if $game_temp
    msgwindow.setSkin(MessageConfig.pbGetSpeechFrame)

    cmdwindow = Window_CommandPokemonEx.new(choices)
    cmdwindow.z = 99999
    cmdwindow.visible = true
    cmdwindow.resizeToFit(cmdwindow.commands)
    pbPositionNearMsgWindow(cmdwindow,msgwindow,:right)
    cmdwindow.index = defaultCmd
    command = 0
    loop do
      @scene.pbUpdateSlotInfo(choice_info[cmdwindow.index])
      Graphics.update
      Input.update
      cmdwindow.update
      msgwindow.update if msgwindow
      if Input.trigger?(Input::BACK)
        command = -1
        break
      end
      if Input.trigger?(Input::USE)
        command = cmdwindow.index
        break
      end
      pbUpdateSceneMap
    end
    ret = command
    cmdwindow.dispose
    msgwindow.dispose
    $game_temp.message_window_showing = false if $game_temp
    Input.update
    return ret
  end

  # Show the player some data about their currently selected save slot for quick identification
  # This doesn't use player gender for coloring, unlike the default save window
  # OPTIMIZED: Uses cached data when available
  def getSaveInfoBoxContents(slot)
    full_path = SaveData.get_full_path(slot)
    if !File.file?(full_path)
      return _INTL("<ac><c3=D0D0C8,3050C8>(Vacío)</c3></ac>")
    end
    
    # Initialize cache if needed
    @save_info_cache ||= {}
    
    # Check if we need to refresh cache (file modified since last read)
    file_mtime = File.mtime(full_path)
    cached_entry = @save_info_cache[slot]
    
    if cached_entry && cached_entry[:mtime] == file_mtime
      return cached_entry[:content]
    end
    
    # Read file and cache the result
    temp_save_data = SaveData.read_from_file(full_path)

    # Last save time
    time = temp_save_data[:player].last_time_saved
    if time
      date_str = time.strftime("%x")
      time_str = time.strftime(_INTL("%I:%M%p"))
      datetime_str = "#{date_str}<r>#{time_str}<br>"
    else
      datetime_str = _INTL("<ac>(Guardado Antiguo)</ac>")
    end

    # Map name
    map_str = pbGetMapNameFromId(temp_save_data[:map_factory].map.map_id)

    # Elapsed time
    totalsec = (temp_save_data[:frame_count] || 0) / Graphics.frame_rate
    # totalsec = $stats.play_time.to_i || 0
    hour = totalsec / 60 / 60
    min = totalsec / 60 % 60
    if hour > 0
      elapsed_str = _INTL("Tiempo<r>{1}h {2}m<br>", hour, min)
    else
      elapsed_str = _INTL("Tiempo<r>{1}m<br>", min)
    end

    content = "<c3=D0D0C8,3050C8>#{datetime_str}</c3>"+ # blue
              "<ac><c3=90F090,209808>#{map_str}</c3></ac>"+ # green
              "#{elapsed_str}"
    
    # Cache the result
    @save_info_cache[slot] = { mtime: file_mtime, content: content }
    
    return content
  end
end

#===============================================================================
#
#===============================================================================
module Game
  # Loads bootup data from save file (if it exists) or creates bootup data (if
  # it doesn't).
  def self.set_up_system
    save_slot = SaveData.get_newest_save_slot
    if save_slot
      save_data = SaveData.read_from_file_safe(SaveData.get_full_path(save_slot), create_backup: false)
    else
      save_data = {}
    end
    if save_data.empty?
      SaveData.initialize_bootup_values
    else
      SaveData.load_bootup_values(save_data)
    end
    # Set resize factor
    pbSetResizeFactor([$PokemonSystem.screensize, 4].min)
    # Set language (and choose language if there is no save file)
    if !Settings::LANGUAGES.empty?
      $PokemonSystem.language = pbChooseLanguage if save_data.empty? && Settings::LANGUAGES.length >= 2
      MessageTypes.load_message_files(Settings::LANGUAGES[$PokemonSystem.language][1])
    end
  end

  # Saves the game. Returns whether the operation was successful.
  # @param save_file [String] the save file path
  # @param safe [Boolean] whether $PokemonGlobal.safesave should be set to true
  # @return [Boolean] whether the operation was successful
  # @raise [SaveData::InvalidValueError] if an invalid value is being saved
  def self.save(slot=nil, auto=false, safe: false)
    slot = $player.save_slot if slot.nil?
    return false if slot.nil?
    
    file_path = SaveData.get_full_path(slot)
    $PokemonGlobal.safesave = safe
    $game_system.save_count += 1
    $game_system.magic_number = $data_system.magic_number
    $stats.set_time_last_saved
    $player.save_slot = slot unless auto
    $player.last_time_saved = Time.now
    # $player.last_save_slot = slot
    begin
      SaveData.save_to_file(file_path)
      Graphics.frame_reset
    rescue IOError, SystemCallError
      $game_system.save_count -= 1
      return false
    end
    return true
  end

  # Overwrites the first empty autosave slot, otherwise the oldest existing autosave
  # OPTIMIZED: Uses file modification time instead of reading save data
  def self.auto_save
    oldest_time = nil
    oldest_slot = nil
    SaveData::AUTO_SLOTS.each do |slot|
      full_path = SaveData.get_full_path(slot)
      if !File.file?(full_path)
        oldest_slot = slot
        break
      end
      # Use file modification time instead of reading the entire save file
      file_mtime = File.mtime(full_path)
      if oldest_time.nil? || file_mtime < oldest_time
        oldest_time = file_mtime
        oldest_slot = slot
      end
    end
    self.save(oldest_slot, true)
  end
end

#===============================================================================
#
#===============================================================================

# Lol who needs the FileUtils gem?
# This is the implementation from the original pbEmergencySave.
def file_copy(src, dst)
  File.open(src, "rb") do |r|
    File.open(dst, "wb") do |w|
      loop do
        s = r.read(4096)
        break if !s
        w.write(s)
      end
    end
  end
end

# When I needed extra data fields in the save file I put them in Player because it seemed easier than figuring out
# how to make a save file conversion, and I prefer to maintain backwards compatibility.
class Player
  attr_accessor :last_time_saved
  attr_accessor :save_slot
  attr_accessor :last_save_slot
  attr_accessor :autosave_steps
end

def pbEmergencySave
  oldscene = $scene
  $scene = nil
  pbMessage(_INTL("El script está tardando mucho. Se va a reiniciar el juego."))
  return if !$player
  return if !$player.save_slot
  current_file = SaveData.get_full_path($player.save_slot)
  backup_file = SaveData.get_backup_file_path
  file_copy(current_file, backup_file)
  if Game.save
    pbMessage("\\se[]" + _INTL("{1} guardó la partida.", $player.name) + "\\me[GUI save game]\\wtnp[20]")
    pbMessage("\\se[]" + _INTL("Se ha hecho una copia del anterior archivo de guardado.") + "\\wtnp[20]")
  else
    pbMessage("\\se[]" + _INTL("El guardado ha fallado.") + "\\wtnp[30]")
  end
  $scene = oldscene
end
# module RTP
#   def self.getSaveFolder
#     # MKXP se asegura de que esta carpeta se haya creado
#     # una vez que comienza. La ubicación difiere según
#     # el sistema operativo:
#     # Windows: %APPDATA%
#     # Linux: $HOME/.local/share
#     # macOS (unsandboxed): $HOME/Library/Application Support
#     "Partidas"
#   end
# end