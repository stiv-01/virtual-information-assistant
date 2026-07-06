extends Node3D

@onready var campo_texto: LineEdit = $CanvasLayer/Control/VBoxContainer/LineEdit
@onready var button: Button = $CanvasLayer/Control/VBoxContainer/Button
@onready var etiqueta_respuesta: RichTextLabel = $CanvasLayer/Control/VBoxContainer/RespuestaIA

var cliente_http = HTTPClient.new()
var enviar_ahora = false 
var interfaz_bloqueada = false 
var buffer_stream = "" # VITAL: Almacena los JSONs que llegan cortados por la red

func _ready():
	button.pressed.connect(_preparar_peticion)
	campo_texto.text_submitted.connect(_preparar_peticion)
	set_process(false) 

func _preparar_peticion(_t = ""):
	var prompt = campo_texto.text
	if prompt == "" or interfaz_bloqueada: return
	
	interfaz_bloqueada = true 
	etiqueta_respuesta.text = "" 
	button.disabled = true
	button.text = "Conectando..."
	campo_texto.editable = false 
	
	var err = cliente_http.connect_to_host("127.0.0.1", 11434)
	if err == OK:
		enviar_ahora = true
		set_process(true)

func _process(_delta):
	cliente_http.poll() 
	var status = cliente_http.get_status()
	
	match status:
		HTTPClient.STATUS_CONNECTED:
			if enviar_ahora:
				_enviar_post_ollama()
				enviar_ahora = false 
				
		HTTPClient.STATUS_BODY:
			if cliente_http.has_response():
				var chunk = cliente_http.read_response_body_chunk()
				if chunk.size() > 0:
					_procesar_fragmento_json(chunk.get_string_from_utf8())
					
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR:
			_finalizar_stream()

func _enviar_post_ollama():
	# INGENIERÍA DE PROMPT: Instrucciones más fuertes para que no divague
	var personalidad = "Eres Levi, un asistente amable. Responde solo en ESPAÑOL de forma clara y directa."
	var body = JSON.stringify({
		"model": "tinyllama", # Cámbialo a "phi3" si sigue hablando raro
		"prompt": personalidad + "\nPregunta: " + campo_texto.text,
		"stream": true, 
		"options": {
			"num_thread": 8,
			"num_gpu": 0,    
			"num_predict": 40,
			"temperature": 0.3, # Subimos un poco para mejorar su lenguaje
			"top_k": 40         # Le damos más vocabulario para que suene natural
		}
	})
	cliente_http.request(HTTPClient.METHOD_POST, "/api/generate", ["Content-Type: application/json"], body)
	campo_texto.text = ""

func _procesar_fragmento_json(texto_crudo: String):
	# 1. Añadimos el nuevo pedazo de red a nuestra memoria
	buffer_stream += texto_crudo
	
	# 2. Partimos por línea
	var lineas = buffer_stream.split("\n")
	
	# 3. El último pedazo casi siempre está incompleto, lo dejamos en el buffer
	buffer_stream = lineas[lineas.size() - 1]
	
	# 4. Procesamos solo las líneas seguras (completas)
	for i in range(lineas.size() - 1):
		var linea = lineas[i]
		if linea.strip_edges() == "": continue
		
		var data = JSON.parse_string(linea)
		
		# Si se pudo convertir a JSON correctamente
		if typeof(data) == TYPE_DICTIONARY:
			if data.has("response"):
				etiqueta_respuesta.text += data["response"]
			
			# ¡AQUÍ ESTÁ LA SOLUCIÓN AL BLOQUEO! 
			# Leemos si la IA ya terminó de hablar
			if data.has("done") and data["done"] == true:
				_finalizar_stream()
				buffer_stream = "" # Limpiamos memoria

func _finalizar_stream():
	set_process(false)
	cliente_http.close()
	
	interfaz_bloqueada = false
	button.disabled = false
	button.text = "ENVIAR PREGUNTA"
	campo_texto.editable = true
