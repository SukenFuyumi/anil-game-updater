#===============================================================================
# Añil - Recordar el nivel de TURBO entre sesiones
#===============================================================================
# El core (067_Scripts de la base/022_Turbo.rb) reinicia $GameSpeed = 0 en cada
# arranque, asi que el turbo se perdia al cerrar el juego. Aqui guardamos el
# nivel en $PokemonSystem.turbo_speed (que persiste con la partida y se carga al
# arrancar, load_in_bootup) cuando cambia, y lo restauramos al cargar la partida.
#
# Solo aplica en modo turbo "Siempre" (only_speedup_battles == 0). En modo
# "Combates" el $GameSpeed lo maneja el propio combate, asi que no se toca.
#===============================================================================
class PokemonSystem
  attr_accessor :turbo_speed
end

module Input
  class << self
    alias_method :anil_turbo_persist_update, :update unless method_defined?(:anil_turbo_persist_update)
    def update
      prev = (defined?($GameSpeed) && $GameSpeed) || 0
      anil_turbo_persist_update
      begin
        if defined?($GameSpeed) && $GameSpeed != prev && $PokemonSystem &&
           $PokemonSystem.respond_to?(:only_speedup_battles) &&
           $PokemonSystem.only_speedup_battles == 0
          $PokemonSystem.turbo_speed = $GameSpeed
        end
      rescue
      end
    end
  end
end

module Game
  class << self
    alias_method :anil_turbo_persist_load, :load unless method_defined?(:anil_turbo_persist_load)
    def load(save_data)
      anil_turbo_persist_load(save_data)
      begin
        if $PokemonSystem && $PokemonSystem.respond_to?(:turbo_speed) &&
           $PokemonSystem.respond_to?(:only_speedup_battles) &&
           $PokemonSystem.only_speedup_battles == 0
          ts = $PokemonSystem.turbo_speed
          if ts.is_a?(Integer) && ts >= 0 && defined?(SPEEDUP_STAGES) && ts < SPEEDUP_STAGES.size
            $GameSpeed = ts
          end
        end
      rescue
      end
    end
  end
end
