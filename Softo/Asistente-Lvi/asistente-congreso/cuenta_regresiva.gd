extends RichTextLabel # O cambia Label por RichTextLabel si elegiste ese nodo

# 1. Definimos la fecha exacta del congreso ICI2ST 2026
# (23 de Septiembre de 2026 a las 08:00 AM)
var fecha_congreso_dict = {
	"year": 2026,
	"month": 9,
	"day": 23,
	"hour": 13,
	"minute": 0,
	"second": 0
}

# Variable para almacenar el tiempo objetivo en formato Unix (segundos desde 1970)
var tiempo_objetivo_unix: int

func _ready():
	# Convertimos la fecha del congreso a un número entero (segundos Unix)
	tiempo_objetivo_unix = Time.get_unix_time_from_datetime_dict(fecha_congreso_dict)
	
	# Llamamos a la función de actualizar una vez al inicio
	_actualizar_reloj()

# La función _process se ejecuta en cada frame (60 veces por segundo)
func _process(_delta):
	_actualizar_reloj()

func _actualizar_reloj():
	# 1. Obtenemos el tiempo actual (Godot lo devuelve como Float)
	var tiempo_actual_unix = Time.get_unix_time_from_system()
	
	# 2. LA SOLUCIÓN TÉCNICA (Casteo): Obligamos a la diferencia a ser un Entero (int) puro
	var diferencia_segundos: int = int(tiempo_objetivo_unix - tiempo_actual_unix)
	
	# 3. Validamos si la fecha ya pasó
	if diferencia_segundos <= 0:
		text = "¡El congreso ICI2ST ha comenzado!"
		set_process(false) # Apagamos el reloj para ahorrar recursos
		return
		
	# 4. Matemáticas de conversión (Ahora la matemática es Int puro, por lo que el '%' funcionará perfecto)
	var dias = diferencia_segundos / 86400
	var horas = (diferencia_segundos % 86400) / 3600
	var minutos = (diferencia_segundos % 3600) / 60
	var segundos = diferencia_segundos % 60
	
	# 5. Formateamos el texto
	var texto_formateado = "Faltan: %d Días - %02d:%02d:%02d" % [dias, horas, minutos, segundos]
	
	# 6. Mostramos en pantalla
	text = texto_formateado
