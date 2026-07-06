extends Node3D

@onready var campo_texto: LineEdit = $MarginContainer/HBoxContainer/LineEdit
@onready var button: Button = $MarginContainer/HBoxContainer/Button
@onready var http_request: HTTPRequest = $HTTPRequest
@onready var http_request_voz: HTTPRequest = $HTTPRequestVoz

# Nodos de la nube de Softo
@onready var nube_dialogo: PanelContainer = $CanvasLayer/Control/NubeDialogo
@onready var etiqueta_respuesta: RichTextLabel = $CanvasLayer/Control/NubeDialogo/RespuestaIA

# Nodos de la nube del usuario
@onready var nube_pregunta: PanelContainer = $CanvasLayer/Control/NubePregunta
@onready var etiqueta_pregunta: RichTextLabel = $CanvasLayer/Control/NubePregunta/PreguntaIA


var id_voz_espanol: String = ""
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var maquina_estados = anim_tree.get("parameters/playback")
@onready var boton_microfono: Button = $MarginContainer/HBoxContainer/Microfono
@onready var reproductor_audio: AudioStreamPlayer = $AudioStreamPlayer
var grabador_audio: AudioEffectRecord
var esta_grabando: bool = false
var ruta_audio: String = "user://pregunta_usuario.wav"
var tiempo_inicio_stt: int = 0
var tiempo_inicio_llm: int = 0
var esta_precalentando: bool = false
var intentos_precalentamiento: int = 0
const MAX_INTENTOS_PRECALENTAMIENTO: int = 4
# 🔴 NUEVO: Variable para guardar la animación de la pregunta y no se cruce si el usuario habla rápido
var tween_animacion_pregunta: Tween

func _ready():
	http_request_voz.request_completed.connect(_al_recibir_transcripcion)
	button.pressed.connect(_enviar_pregunta_a_ia)
	campo_texto.text_submitted.connect(_enviar_pregunta_a_ia)
	http_request.request_completed.connect(_al_recibir_respuesta)

	http_request.timeout = 30.0

	nube_dialogo.modulate.a = 0.0
	nube_dialogo.visible = false
	etiqueta_respuesta.bbcode_enabled = true
	etiqueta_respuesta.text = "[color=black]Softo está listo para tus preguntas...[/color]"

	nube_pregunta.modulate.a = 0.0
	nube_pregunta.visible = false
	etiqueta_pregunta.bbcode_enabled = true

	anim_tree.active = true
	maquina_estados.start("Respirar")
	
	var voces = DisplayServer.tts_get_voices()
	for voz in voces:
		if voz.language.begins_with("es"):
			id_voz_espanol = voz.id
			print("DEBUG - Voz seleccionada: ", voz.name)
			break
	if id_voz_espanol == "":
		print("ADVERTENCIA: No se encontró una voz en español.")
		
	boton_microfono.pressed.connect(_alternar_grabacion)
	var indice_bus = AudioServer.get_bus_index("Record")
	grabador_audio = AudioServer.get_bus_effect(indice_bus, 0)

	_precalentar_modelo()

func _precalentar_modelo():
	esta_precalentando = true
	intentos_precalentamiento += 1
	
	# ✅ NUEVO: timeout creciente por cada intento (60s, 90s, 120s)
	http_request.timeout = 60.0 + (intentos_precalentamiento - 1) * 30.0
	
	etiqueta_respuesta.text = "[color=#ff5f1f]⏳ Empezando, por favor espere...[/color]"
	nube_dialogo.modulate.a = 1.0
	nube_dialogo.visible = true
	button.disabled = true
	campo_texto.editable = false
	boton_microfono.disabled = true
	print("DEBUG - Precalentando modelo en RAM... Intento ", intentos_precalentamiento, " | Timeout: ", http_request.timeout, "s")

	var payload = {
		"model": "softo_congreso",
		"prompt": "hola",
		"stream": false,
		"keep_alive": "10m",
		"options": {
			"num_thread": 6,
			"temperature": 0.1,
			"num_gpu": 0,
			"num_predict": 20
		}
	}
	var json_data = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	http_request.request("http://127.0.0.1:11434/api/generate", headers, HTTPClient.METHOD_POST, json_data)
	_animar_puntos_carga()

func _animar_puntos_carga():
	var puntos = 0
	while esta_precalentando:
		puntos = (puntos % 3) + 1
		var dots = ".".repeat(puntos)
		etiqueta_respuesta.text = "[color=#ff5f1f]⏳ Empezando, por favor espere" + dots + "[/color]"
		await get_tree().create_timer(0.5).timeout

func _limpiar_texto(texto: String) -> String:
	var lineas = texto.split("\n")
	var lineas_limpias: Array = []

	for linea in lineas:
		var lower = linea.to_lower()
		var es_interna = (
			"responder con" in lower or
			"por las reglas" in lower or
			"frase designada" in lower or
			"datos oficiales" in lower or
			"regla " in lower or
			linea.begins_with("##") or
			linea.begins_with("**")
		)
		if not es_interna:
			lineas_limpias.append(linea)

	var resultado = "\n".join(lineas_limpias).strip_edges()
	resultado = resultado.replace("**", "").replace("##", "")
	return resultado

func _enviar_pregunta_a_ia(_texto_ignorado = ""):
	var texto_usuario = campo_texto.text
	if texto_usuario == "": return

	button.disabled = true
	button.text = "..."
	campo_texto.editable = false
	boton_microfono.disabled = true

	# Configurar texto y mostrar nube del usuario
	etiqueta_pregunta.text = "[color=blue]Tú:[/color] " + texto_usuario
	nube_pregunta.visible = true
	
	# Mostrar nube de IA
	nube_dialogo.visible = true
	etiqueta_respuesta.visible_characters = -1
	etiqueta_respuesta.text = "Softo está pensando..."

	# Animamos la nube de IA para que aparezca
	var tween_aparecer_ia = get_tree().create_tween()
	tween_aparecer_ia.tween_property(nube_dialogo, "modulate:a", 1.0, 0.4)

	# 🔴 NUEVO: Control independiente de la Nube de Pregunta
	# Si ya había un contador corriendo, lo matamos para que no parpadee
	if tween_animacion_pregunta and tween_animacion_pregunta.is_valid():
		tween_animacion_pregunta.kill()
	
	# Creamos un nuevo animador que aparece, espera 10s y desaparece solo
	tween_animacion_pregunta = get_tree().create_tween()
	tween_animacion_pregunta.tween_property(nube_pregunta, "modulate:a", 1.0, 0.4)
	tween_animacion_pregunta.tween_interval(10.0) # Esperar exactamente 10 segundos
	tween_animacion_pregunta.tween_property(nube_pregunta, "modulate:a", 0.0, 0.4)
	tween_animacion_pregunta.tween_callback(func(): nube_pregunta.visible = false)

	var payload = {
		"model": "softo_congreso",
		"prompt": texto_usuario,
		"stream": false,
		"keep_alive": "10m",
		"options": {
			"num_thread": 6,
			"temperature": 0.1,
			"num_gpu": 0,
			"num_predict": 200,
		}
	}

	var json_data = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	tiempo_inicio_llm = Time.get_ticks_msec()
	print("DEBUG - Pregunta enviada a Softo: ", texto_usuario)
	http_request.request("http://127.0.0.1:11434/api/generate", headers, HTTPClient.METHOD_POST, json_data)
	campo_texto.text = ""

func _al_recibir_respuesta(resultado, codigo, _cabeceras, cuerpo):
	if esta_precalentando:
		esta_precalentando = false

		if codigo == 200:
			etiqueta_respuesta.text = "[color=black]✅ ¡Softo está listo! ¿En qué puedo ayudarte?[/color]"
			print("DEBUG - Modelo precalentado y listo en RAM.")
			http_request.timeout = 30.0  # ✅ restaura el timeout normal para preguntas
			_restaurar_interfaz("")
		else:
			# ✅ NUEVO: reintenta automáticamente si no se alcanzó el máximo
			if intentos_precalentamiento < MAX_INTENTOS_PRECALENTAMIENTO:
				print("ADVERTENCIA - Intento ", intentos_precalentamiento, " fallido. Reintentando...")
				etiqueta_respuesta.text = "[color=#ff5f1f]⏳ Cargando modelo, reintentando...[/color]"
				await get_tree().create_timer(1.5).timeout
				_precalentar_modelo()
				return
			else:
				# Solo aquí, tras 3 intentos reales, mostramos error definitivo
				if resultado == HTTPRequest.RESULT_TIMEOUT:
					etiqueta_respuesta.text = "[color=red]❌ Timeout: Ollama tardó demasiado. Verifica que esté encendido.[/color]"
				else:
					etiqueta_respuesta.text = "[color=red]❌ Error: Ollama no responde. Abre CMD y ejecuta: ollama serve[/color]"
				print("ERROR - Fallo definitivo tras ", MAX_INTENTOS_PRECALENTAMIENTO, " intentos. Código: ", codigo)

		await get_tree().create_timer(3.0).timeout
		if not button.disabled:
			var tween = get_tree().create_tween()
			tween.tween_property(nube_dialogo, "modulate:a", 0.0, 0.5)
			await tween.finished
			nube_dialogo.visible = false
		return

	var tiempo_total_llm = (Time.get_ticks_msec() - tiempo_inicio_llm) / 1000.0
	print("📊 MÉTRICA LLM: ", tiempo_total_llm, " segundos.")
	var texto_crudo = cuerpo.get_string_from_utf8()
	print("--- REPORTE DE RED ---")
	print("Código HTTP: ", codigo)
	print("Respuesta: ", texto_crudo)
	print("----------------------")

	if codigo == 200:
		var respuesta_json = JSON.parse_string(texto_crudo)
		if typeof(respuesta_json) == TYPE_DICTIONARY and respuesta_json.has("response"):
			var texto_ia = respuesta_json["response"].strip_edges()
			texto_ia = _limpiar_texto(texto_ia)
			_animar_texto(texto_ia)
		else:
			etiqueta_respuesta.visible_characters = -1
			etiqueta_respuesta.text = "[color=orange]Formato de respuesta inválido.[/color]"
			_restaurar_interfaz("")
	else:
		etiqueta_respuesta.visible_characters = -1
		if resultado == HTTPRequest.RESULT_TIMEOUT:
			etiqueta_respuesta.text = "[color=red]Timeout: Softo tardó demasiado. Intenta de nuevo.[/color]"
		elif codigo == 0:
			etiqueta_respuesta.text = "[color=red]Error 0: Ollama está APAGADO.[/color]"
		else:
			etiqueta_respuesta.text = "[color=red]Error " + str(codigo) + ": " + texto_crudo + "[/color]"
		_restaurar_interfaz("")

func _restaurar_interfaz(mensaje_boton: String):
	button.disabled = false
	button.text = mensaje_boton if mensaje_boton != "" else ""
	campo_texto.editable = true
	boton_microfono.disabled = false

func _animar_texto(texto_completo: String):
	etiqueta_respuesta.text = texto_completo
	etiqueta_respuesta.visible_characters = 0
	maquina_estados.travel("Hablar")
	if id_voz_espanol != "":
		DisplayServer.tts_speak(texto_completo, id_voz_espanol, 80, 1, 1)
	var tween = get_tree().create_tween()
	var duracion = texto_completo.length() * 0.065
	tween.tween_property(etiqueta_respuesta, "visible_characters", texto_completo.length(), duracion)
	_sincronizar_animacion_y_voz(tween)

func _sincronizar_animacion_y_voz(tween: Tween):
	await tween.finished
	if id_voz_espanol != "":
		while DisplayServer.tts_is_speaking():
			await get_tree().create_timer(0.1).timeout
	_al_terminar_de_hablar()

func _al_terminar_de_hablar():
	await get_tree().create_timer(3.5).timeout
	maquina_estados.travel("Respirar")
	# 🔴 NUEVO: Ahora solo la nube de IA se desvanece por aquí. 
	# La de pregunta se desvanece por sí sola a los 10 segundos.
	var tween_desvanecer = get_tree().create_tween()
	tween_desvanecer.tween_property(nube_dialogo, "modulate:a", 0.0, 0.4)
	await tween_desvanecer.finished
	
	nube_dialogo.visible = false
	_restaurar_interfaz("")

func _alternar_grabacion():
	if esta_grabando:
		_detener_grabacion()
	else:
		_iniciar_grabacion()

func _iniciar_grabacion():
	esta_grabando = true
	boton_microfono.modulate = Color(1, 0, 0)
	campo_texto.editable = false
	button.disabled = true
	grabador_audio.set_recording_active(true)
	reproductor_audio.play()
	print("DEBUG - Micrófono ABIERTO")

func _detener_grabacion():
	esta_grabando = false
	boton_microfono.modulate = Color(1, 1, 1)
	grabador_audio.set_recording_active(false)
	reproductor_audio.stop()
	print("DEBUG - Micrófono CERRADO")
	var grabacion = grabador_audio.get_recording()
	if grabacion:
		var error_guardado = grabacion.save_to_wav(ruta_audio)
		if error_guardado == OK:
			print(">>> Audio guardado. Enviando a Python...")
			_enviar_audio_a_python()
		else:
			print("ERROR: No se pudo guardar el .wav")
			_restaurar_interfaz("")
	else:
		print("ERROR: Micrófono sin audio.")
		_restaurar_interfaz("")

func _enviar_audio_a_python():
	if not nube_dialogo.visible:
		nube_dialogo.modulate.a = 0.0
		nube_dialogo.visible = true
		var tween_aparecer = get_tree().create_tween()
		tween_aparecer.tween_property(nube_dialogo, "modulate:a", 1.0, 0.4)
	etiqueta_respuesta.visible_characters = -1
	etiqueta_respuesta.text = "Softo te está escuchando..."
	var boundary = "GodotVozBoundary12345"
	var body = PackedByteArray()
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"audio\"; filename=\"pregunta.wav\"\r\n".to_utf8_buffer())
	body.append_array("Content-Type: audio/wav\r\n\r\n".to_utf8_buffer())
	var archivo_bytes = FileAccess.get_file_as_bytes(ruta_audio)
	body.append_array(archivo_bytes)
	body.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())
	var headers = ["Content-Type: multipart/form-data; boundary=" + boundary]
	tiempo_inicio_stt = Time.get_ticks_msec()
	http_request_voz.request_raw("http://127.0.0.1:5000/transcribir", headers, HTTPClient.METHOD_POST, body)

func _al_recibir_transcripcion(_resultado, codigo, _cabeceras, cuerpo):
	if codigo == 200:
		var tiempo_total_stt = (Time.get_ticks_msec() - tiempo_inicio_stt) / 1000.0
		print("📊 MÉTRICA STT: ", tiempo_total_stt, " segundos.")
		var texto_crudo = cuerpo.get_string_from_utf8()
		var respuesta_json = JSON.parse_string(texto_crudo)
		if typeof(respuesta_json) == TYPE_DICTIONARY and respuesta_json.has("texto"):
			var texto_transcrito = respuesta_json["texto"]
			print(">>> Python entendió: ", texto_transcrito)
			campo_texto.text = texto_transcrito
			
			_enviar_pregunta_a_ia()
		else:
			_restaurar_interfaz("")
			etiqueta_respuesta.text = "[color=orange]Error al leer transcripción.[/color]"
	else:
		_restaurar_interfaz("")
		etiqueta_respuesta.text = "[color=red]Error con Python. ¿Está encendido el servidor?[/color]"

func _on_salir_pressed() -> void:
	get_tree().quit()
func _on_boton_reiniciar_pressed() -> void:
	OS.set_restart_on_exit(true)
	get_tree().quit()
