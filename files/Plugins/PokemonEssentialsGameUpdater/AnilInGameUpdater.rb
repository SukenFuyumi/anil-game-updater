#===============================================================================
# Añil - Updater IN-GAME (Ruby puro; funciona en PC y en Android/NaviaXP/JoiPlay)
#===============================================================================
# El updater normal (anil_updater.exe) es un binario de Windows y NO puede correr
# en Android. Este modulo hace la MISMA actualizacion por deltas pero en Ruby,
# dentro del motor del juego, asi que sirve en movil sin redescargar todo.
#
# Flujo: baja manifest-lite.txt, compara CRC32 de cada archivo local, baja SOLO
# los distintos a "<ruta>.anilnew", verifica, y los aplica. Si algo falla ->
# devuelve false y el llamador usa el metodo antiguo (link de descarga).
#
# NOTAS Android:
#  - El HTTPLite convierte CRLF->LF al bajar TEXTO (binarios .rxdata intactos):
#    por eso el CRC ignora los bytes CR (0x0D) en ambos lados (aqui y gen-manifest).
#  - Sobrescribir un archivo existente no siempre persiste; se BORRA y se recrea,
#    y se hace fsync para forzar el volcado a disco.
#
# No usa JSON ni Digest::SHA256 (mkxp-z no los garantiza): solo Zlib + File.
#===============================================================================
module AnilInGameUpdater
  LITE_URL = "https://raw.githubusercontent.com/SukenFuyumi/anil-game-updater/main/manifest-lite.txt"

  module_function

  def url_encode_segment(seg)
    out = ""
    seg.each_byte do |b|
      ch = b.chr
      if ch =~ /[A-Za-z0-9\-_.~]/
        out << ch
      else
        out << format("%%%02X", b)
      end
    end
    out
  end

  def encode_path(relpath)
    relpath.split("/").map { |s| url_encode_segment(s) }.join("/")
  end

  def read_bin(relpath)
    File.open(relpath, "rb") { |f| f.read }
  end

  def write_bin(relpath, data)
    File.open(relpath, "wb") do |f|
      f.write(data)
      f.flush
      (f.fsync rescue nil)   # forzar volcado a disco (Android no persiste sin esto)
    end
  end

  # CRC32 insensible a CR (0x0D): el HTTPLite de Android convierte CRLF->LF al
  # bajar texto, asi que comparamos ignorando los CR en ambos lados.
  def crc_norm(data)
    Zlib.crc32(data.delete("\r"))
  end

  def local_crc(relpath)
    return nil unless File.file?(relpath)
    begin
      crc_norm(read_bin(relpath))
    rescue
      nil
    end
  end

  # Devuelve true SOLO si aplico una actualizacion (el llamador debe reiniciar).
  def run
    data = (pbDownloadToString(LITE_URL) rescue "")
    return false if data.nil? || !data.is_a?(String) || data.empty?

    lines = data.split("\n")
    return false if lines.length < 3
    version = lines[0].strip
    base    = lines[1].strip
    return false if base.empty?

    entries = []
    lines[2..-1].each do |ln|
      next if ln.nil? || ln.strip.empty?
      parts = ln.split("\t", 3)
      next if parts.length < 3
      entries.push({ :crc => parts[0].to_i, :size => parts[1].to_i, :path => parts[2] })
    end
    return false if entries.empty?

    changed = (entries.select { |e| local_crc(e[:path]) != e[:crc] } rescue nil)
    return false if changed.nil? || changed.empty?

    total_mb = ((changed.map { |e| e[:size] }.sum / 1048576.0) * 10).round / 10.0
    if !pbConfirmMessage(_INTL("Hay una actualización disponible ({1} archivo(s), {2} MB). ¿Descargar e instalar ahora?", changed.length, total_mb))
      return false
    end

    # --- Fase 1: descargar a .anilnew y verificar CRC ---
    staged = []
    ok = true
    msgwin = pbCreateMessageWindow
    begin
      changed.each_with_index do |e, i|
        pbMessageDisplay(msgwin, _INTL("Descargando actualización...\n{1} / {2}", i + 1, changed.length), false)
        Graphics.update
        Input.update
        url = base + "/" + encode_path(e[:path])
        tmp = e[:path] + ".anilnew"
        File.delete(tmp) rescue nil
        pbDownloadToFile(url, tmp)
        if !File.file?(tmp) || (crc_norm(read_bin(tmp)) rescue -1) != e[:crc]
          File.delete(tmp) rescue nil
          ok = false
          break
        end
        staged.push([tmp, e[:path]])
      end
    rescue
      ok = false
    end
    pbDisposeMessageWindow(msgwin)

    if !ok
      staged.each { |t, _| File.delete(t) rescue nil }
      pbMessage(_INTL("No se pudo completar la descarga de la actualización.\nSe intentará por el método alternativo."))
      return false
    end

    # --- Fase 2: aplicar (sobrescritura simple; NUNCA borra el archivo original
    # para no perderlo si la escritura no persiste). ---
    applied = true
    staged.each do |tmp, real|
      begin
        write_bin(real, read_bin(tmp))
      rescue
        applied = false
        next
      end
      File.delete(tmp) rescue nil
    end

    if !applied
      pbMessage(_INTL("Hubo un problema aplicando la actualización.\nCierra el juego y vuelve a intentarlo."))
      return false
    end

    pbMessage(_INTL("¡Actualización a la versión {1} completada!", version))
    pbMessage(_INTL("El juego se cerrará ahora. Ábrelo de nuevo para aplicar los cambios."))
    return true
  end
end
