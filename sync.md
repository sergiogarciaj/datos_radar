# Sincronización de Consultas (Radar vs BD Local Seldon)

La aplicación Seldon (`bq_metadata_manager`) no lee las consultas SQL directamente de los archivos en el disco para la sección de "Consultas Guardadas". En su lugar, el código SQL se almacena en la tabla `saved_queries` de una base de datos **PostgreSQL** local (`bq_metadata_db`), a la que accede el contenedor Docker `bq_manager_api`.

Cuando editas archivos locales en el directorio `/radar/` (como `sgj_calculated_act.sql`), estos cambios no se reflejan en la interfaz web de Seldon a menos que inyectes ese texto dentro de la base de datos.

## Cómo sincronizar manualmente (Script Python)

Para facilitar este proceso, puedes guardar el siguiente código en un archivo llamado `sync_query.py` en la raíz de tu proyecto (o ejecutarlo según necesites). Este script toma un archivo `.sql` de radar y lo inyecta en la base de datos de PostgreSQL usando el contenedor de backend.

```python
import sys
import os

if len(sys.argv) < 2:
    print("Uso: python3 sync_query.py <nombre_query_sin_extension>")
    print("Ejemplo: python3 sync_query.py sgj_calculated_act")
    sys.exit(1)

query_name = sys.argv[1]
file_path = f"/home/sergio/seldon/radar/{query_name}.sql"

if not os.path.exists(file_path):
    print(f"Error: No se encontró el archivo {file_path}")
    sys.exit(1)

with open(file_path, 'r') as f:
    sql_content = f.read()

# Escribe un script temporal que SQLAlchemy pueda ejecutar dentro del contenedor
python_code = f"""
from database import SessionLocal
from models import SavedQuery

db = SessionLocal()
query = db.query(SavedQuery).filter(SavedQuery.name == '{query_name}').first()
if query:
    query.sql_query = {repr(sql_content)}
    db.commit()
    print(f"✅ '{{query_name}}' ha sido actualizada en la base de datos Seldon.")
else:
    print(f"❌ La consulta '{{query_name}}' no existe en la base de datos. Debes crearla primero en la interfaz.")
"""

temp_script_path = '/home/sergio/seldon/bq_metadata_manager/backend/temp_update.py'

# Creamos el archivo dentro de la carpeta mapeada en docker-compose
with open(temp_script_path, 'w') as f:
    f.write(python_code)

# Ejecutamos el script usando el entorno Python de Docker (que ya tiene SQLAlchemy configurado)
os.system('docker exec bq_manager_api python temp_update.py')

# Borramos la evidencia temporal
os.remove(temp_script_path)
```

### Ejecución:
Si guardas este código en `/home/sergio/seldon/sync_query.py`, puedes sincronizar cualquier consulta de las tablas del flujo de Radar simplemente corriendo en tu terminal.

Las consultas soportadas y registradas en la base de datos de Seldon son:
* **Calculadas (Calculated):** `sgj_calculated` / `sgj_calculated_act`
* **Intermedias (Intermediate):** `sgj_intermedia` / `sgj_intermedia_act`
* **Finales (Third):** `sgj_third` / `sgj_third_act`

Ejemplo para ejecutar la sincronización:
```bash
cd /home/sergio/seldon
python3 sync_query.py sgj_calculated_act
python3 sync_query.py sgj_intermedia_act
python3 sync_query.py sgj_third_act
```
