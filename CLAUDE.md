# CLAUDE.md — ElGremio (TuManitas)
> Contexto global para Claude Code. Este fichero se lee automáticamente al inicio de cada sesión.
> Última actualización: Mayo 2026 | Versión definición técnica: 2.0

---

## 1. Qué es este proyecto

**ElGremio** es un marketplace de servicios del hogar (fontaneros, electricistas, pintores, etc.) con ámbito MVP en Málaga. La plataforma conecta clientes con profesionales mediante dos modalidades: contacto directo por teléfono (perfiles no reclamados, importados por scraping) y reserva con precio cerrado vía app (perfiles reclamados/verificados).

**Repo GitHub:** `RodrigoSuiffet/tuManitas`
**Gestión de tareas:** Linear — proyecto `TuManitas` (team ID: `016ab707-a31a-477d-9e2a-ef04aa7ad031`)
**Convención de ramas:** usar **exactamente** el campo `gitBranchName` del issue de Linear (ej: `rsuiffet/tum-52-e6-t1-flyway-migration-reservas`)

---

## 2. Stack tecnológico — decisiones cerradas

### Backend
| Tecnología | Versión | Notas |
|---|---|---|
| Java | 21 (LTS) | Records, virtual threads, pattern matching |
| Spring Boot | 3.3 | |
| Spring Security | 6 | JWT + RBAC. Filtro `JwtAuthenticationFilter` |
| Spring Data JPA | (Hibernate 6) | Repositorios tipados. Sin JPQL nativo salvo necesidad justificada |
| Spring Validation | — | `@Valid`, `@NotNull`, `@Size` en todos los DTOs de entrada |
| Spring Events | — | Comunicación asíncrona interna entre módulos |
| Spring Scheduler | — | Jobs periódicos: borrado fotos, recálculo puntuación, expiración suscripciones |
| Flyway | — | Toda modificación de esquema **requiere** migración versionada. Sin excepciones |
| MapStruct | — | Mapping entidad ↔ DTO. Sin reflexión en runtime |
| Lombok | — | `@Data`, `@Builder`, `@Slf4j` en entidades y DTOs |
| Bucket4j | — | Rate limiting en memoria |
| Apache Tika | — | Validación MIME real de ficheros subidos |
| Maven | — | Build y gestión de dependencias |

### Frontend
| Tecnología | Versión | Notas |
|---|---|---|
| React | 18.x | |
| TypeScript | 5.x | **Obligatorio** en todo el proyecto. Sin `any` |
| Vite | 5.x | Dev server y build tool |
| Redux Toolkit | 2.x | Estado global: auth, carrito, preferencias |
| RTK Query | (incluido RTK) | **Todo** el server state. No usar React Query ni fetch manual |
| React Router | v6 | Rutas protegidas por rol |
| React Hook Form | 7.x | Formularios. Con validación Zod |
| Zod | 3.x | Validación de esquemas en cliente |
| Tailwind CSS | 3.x | Tokens de diseño en `tailwind.config.js` |
| shadcn/ui | latest | Componentes base (Radix UI) |
| Leaflet + react-leaflet | 4.x | Mapas. Sin coste de API por mapa renderizado |
| Axios | 1.x | HTTP con interceptores JWT + refresh automático |
| dayjs | 1.x | Fechas. Sin moment.js |
| Vitest + Testing Library | latest | Tests unitarios y de componente |

### Base de datos
- **PostgreSQL 16** + extensión **PostGIS**
- `GEOGRAPHY(POINT, 4326)` en tabla `profesionales`. Índice GIST obligatorio
- `pg_trgm` para búsqueda fuzzy (detección de duplicados)
- `JSONB` en `audit_log` para `datos_anteriores` / `datos_nuevos`
- PKs: `UUID` generados con `gen_random_uuid()`
- Timestamps en **UTC**. `created_at DEFAULT NOW()`, `updated_at` via trigger

### Almacenamiento
| Bucket S3 | ACL | Contenido | Retención |
|---|---|---|---|
| `elgremio-public` | Público lectura | Fotos portfolio, fotos valoraciones públicas | Indefinida |
| `elgremio-private` | Privado + Pre-signed URLs (TTL 15 min) | Fotos verificación (DNI, trabajo) | 30 días → borrado automático |
| `elgremio-docs` | Privado (solo backoffice) | CIF, certificados de reclamaciones | 90 días tras resolución |

### Infraestructura AWS
- **ECS Fargate** — backend Spring Boot (Docker, sin EC2)
- **RDS PostgreSQL 16** — `db.t3.medium`, 20 GB SSD
- **CloudFront** — CDN para frontend y assets públicos
- **ALB** — terminación SSL, health checks
- **ECR** — registro Docker (`elgremio-backend`)
- **Secrets Manager** — todas las credenciales. **Nunca** en código ni en `application.yml` de producción
- **CloudWatch** — alarmas en error rate >1% y latencia p99 >2s

### Comunicaciones
- **Email:** SendGrid (SDK Java + plantillas Handlebars)
- **Push:** Firebase Cloud Messaging (Admin SDK Java)
- **In-app:** tabla `notificaciones` en PostgreSQL (RTK Query con refetch en window focus)
- **SMS/OTP:** Twilio — **fuera del MVP**, solo preparar abstracción `SmsService`

---

## 3. Arquitectura

### Patrón: Monolito Modular
13 módulos Spring Boot comparten proceso y BD, con límites de responsabilidad estrictos. Cada módulo expone funciones **solo a través de interfaces de servicio**, nunca accediendo directamente a repositorios de otro módulo.

### Módulos (packages)
| Módulo | Descripción |
|---|---|
| `auth` | Registro, login, JWT, refresh token, recuperación de contraseña |
| `users` | Gestión de clientes: perfil, historial, preferencias, exportación RGPD |
| `professionals` | Perfil público/privado, búsqueda geolocalizada, fotos de portfolio |
| `companies` | Cuentas de empresa, vinculación de profesionales |
| `services` | Servicios y precios, disponibilidad por profesional |
| `bookings` | Reservas (app y teléfono), estados, confirmaciones |
| `reviews` | Valoraciones, fotos públicas/privadas, moderación |
| `claims` | Reclamación de perfil, detección de duplicados, regla de bloqueo (≥3 pendientes → HTTP 409) |
| `subscriptions` | Suscripción anual 10€, ciclo de facturación, visibilidad destacada |
| `notifications` | Notificaciones push/email/in-app, tokens FCM |
| `backoffice` | Panel admin: moderación, métricas, dashboard KPIs |
| `scraper` | API de importación, staging, normalización, deduplicación |
| `audit` | Registro de acciones críticas via `@Aspect` |
| `common` | Paginación, excepciones, `ApiResponse<T>`, constantes, validadores |

### Capas por módulo
```
Controller  →  valida DTO (@Valid), delega al service, devuelve ApiResponse<T>
Service     →  lógica de negocio, @Transactional, orquestación
Repository  →  JPA/JPQL, acceso a datos
Domain/DTO  →  @Entity, Java records para request/response, MapStruct mappers
Infrastructure → S3Client, FcmClient, SendGridClient, MapsClient
Security    →  JwtAuthFilter, SecurityConfig, @PreAuthorize
Audit Aspect → intercepta @Auditable, graba en audit_log
```

---

## 4. Seguridad — reglas no negociables

### JWT
- **Access Token:** RS256, TTL 15 minutos, almacenado en memoria JS (**nunca** localStorage)
- **Refresh Token:** opaco (UUID v4), TTL 7 días, cookie HttpOnly + Secure + SameSite=Strict
- Rotación simple: cada `/auth/refresh` invalida el anterior
- Clave privada en **Secrets Manager**

### RBAC — roles
| Rol | Permisos |
|---|---|
| `ROLE_CLIENT` | Buscar, reservar, valorar, ver historial propio |
| `ROLE_PROFESSIONAL` | Todo CLIENT + gestionar perfil propio, ver sus reservas, registrar contrataciones telefónicas |
| `ROLE_COMPANY_ADMIN` | Todo PROFESSIONAL + gestionar profesionales de su empresa |
| `ROLE_BACKOFFICE` | Moderar, validar reclamaciones, ver audit log, editar cualquier perfil |
| `ROLE_ADMIN` | Todo BACKOFFICE + importaciones masivas, gestión de agentes backoffice |

**Propiedad del recurso:** además del rol, verificar siempre que el usuario sea propietario:
```java
if (!recurso.getUsuarioId().equals(authUserId)) throw new ForbiddenException();
```
Esta comprobación va **antes** de cualquier modificación.

### Medidas adicionales
- **Rate limiting (Bucket4j):** 100 req/min por IP en endpoints públicos; 10 req/min en `/auth/login` y `/auth/forgot-password`
- **CORS:** solo `https://elgremio.es` en producción; `localhost:5173` en dev
- **Ficheros subidos:** validar MIME con Apache Tika (no confiar en el header del cliente). Máx 5 MB fotos, 10 MB documentos. Extensiones: `jpg, jpeg, png, webp, pdf`
- **Pre-signed URLs:** fotos privadas nunca exponen URL directa de S3. TTL 15 min, registrar en `audit_log`
- **Security headers:** `Content-Security-Policy`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin`
- **HTTPS obligatorio:** TLS 1.3, HSTS en headers

### RGPD
- Borrado de cuenta: anonimizar campos personales (nombre → "Usuario eliminado", email → SHA-256). Mantener reservas y valoraciones anonimizadas
- Fotos privadas: doble mecanismo de borrado a 30 días — S3 Lifecycle Rule + Spring Scheduler semanal
- IPs en `audit_log`: hashear (SHA-256) tras 90 días
- Consentimiento en registro: checkbox explícito, guardar versión y timestamp en `usuario.privacidad_aceptada_v` y `privacidad_aceptada_at`

---

## 5. Modelo de datos — tablas principales

### Convenciones globales
- PK: `UUID` con `gen_random_uuid()`
- Timestamps en UTC: `created_at TIMESTAMP NOT NULL DEFAULT NOW()`, `updated_at` via trigger
- Borrado lógico: campo `activo BOOLEAN` o campo `estado ENUM`
- **Nunca** borrado físico de registros de negocio

### Tablas críticas
```
usuarios          — clientes y profesionales registrados
profesionales     — perfiles (scrapeados y registrados). PostGIS GEOGRAPHY
categorias        — fontanero, electricista, etc.
empresas          — cuentas multi-profesional
servicios_precios — catálogo de servicios con precio por profesional
disponibilidad    — franjas horarias por día de semana o fecha específica
reservas          — canal: app | telefono. Estados: pendiente → confirmada → completada | cancelada | rechazada
valoraciones      — verificadas (reserva_app / telefono_confirmado / manual_backoffice) y no verificadas
fotos_valoracion  — fotos públicas en reseñas (elgremio-public)
fotos_verificacion — fotos privadas, borrado a 30 días (elgremio-private)
fotos_profesional — portfolio del profesional (elgremio-public)
reclamaciones_perfil — workflow: pendiente → aprobada | rechazada | cancelada | bloqueada
suscripciones     — plan pro_anual (10€/año), UNIQUE por profesional
audit_log         — BIGSERIAL PK, todas las acciones críticas
notificaciones    — in-app persistidas
tokens_push       — tokens FCM por usuario
```

### Restricciones críticas a recordar
- `UNIQUE (cliente_id, reserva_id)` en `valoraciones` — no se puede valorar dos veces la misma reserva
- `UNIQUE profesional_id` en `suscripciones` — solo una suscripción activa por profesional
- Reclamación bloqueada si el perfil ya tiene **≥ 3 pendientes** → HTTP 409
- Perfiles con `estado IN (reclamado, verificado)` **nunca** se sobreescriben con datos del scraper

---

## 6. API REST — convenciones

### Estructura de respuesta
```java
// Éxito
ApiResponse<T> { success: true, data: T, message: null }

// Error
ApiResponse<T> { success: false, data: null, message: "Descripción del error" }
```

### Rutas base
```
/api/v1/auth/...           — registro, login, refresh, me
/api/v1/users/...          — gestión de clientes
/api/v1/professionals/...  — perfiles y búsqueda pública
/api/v1/bookings/...       — reservas
/api/v1/reviews/...        — valoraciones
/api/v1/claims/...         — reclamaciones
/api/v1/subscriptions/...  — suscripciones
/api/v1/notifications/...  — notificaciones in-app + SSE
/api/v1/admin/...          — panel backoffice (ROLE_BACKOFFICE+)
/api/v1/import/...         — importación scraping (ROLE_ADMIN)
```

### Paginación
```java
// Request: ?page=0&size=20&sort=createdAt,desc
Page<T>  // Spring Data Pageable
```

### Códigos HTTP
- `200` — OK con body
- `201` — Created (POST que crea un recurso)
- `202` — Accepted (reclamación detecta posible duplicado → revisión manual)
- `204` — No Content (DELETE o acciones sin body de respuesta)
- `400` — Validación fallida
- `401` — Sin autenticación
- `403` — Autenticado pero sin permiso (o no es propietario del recurso)
- `404` — Recurso no encontrado
- `409` — Conflicto (ej: reclamación bloqueada por ≥3 pendientes)
- `429` — Rate limit superado

---

## 7. Tests — cobertura obligatoria

Cada tarea de desarrollo **debe incluir** tests. No es opcional.

### Backend
```java
// Tests unitarios — JUnit 5 + Mockito
@ExtendWith(MockitoExtension.class)
// Mockear dependencias externas (S3, FCM, SendGrid, NotificationService)
// Cubrir: happy path, validaciones, excepciones de negocio

// Tests de integración — Testcontainers
@Container static PostgreSQLContainer<?> postgres = 
    new PostgreSQLContainer<>("postgis/postgis:16-3.4").withReuse(true);
// Sin @MockBean salvo excepciones justificadas
// Cubrir: endpoints HTTP completos, control de acceso por rol, ownership checks
```

### Frontend
```typescript
// Vitest + Testing Library
// Cubrir: renderizado de componentes, interacciones de usuario
// RTK Query: mockear con MSW (Mock Service Worker)
```

### Qué testear obligatoriamente
- Control de acceso por rol en cada endpoint (`ROLE_CLIENT` no puede acceder a `/admin/...`)
- Ownership checks (usuario A no puede modificar recursos de usuario B)
- Máquinas de estado (reservas, reclamaciones, suscripciones)
- Lógica de negocio crítica (bloqueo ≥3 reclamaciones, borrado a 30 días, recálculo puntuación)
- Integración con `audit_log` donde corresponda

---

## 8. Audit Log — cuándo y cómo

El `audit_log` registra **todas** las acciones críticas. Usar `@Auditable` en los métodos de servicio relevantes, o llamar directamente a `AuditLogService.log()`.

### Acciones que **siempre** deben auditarse
```
REGISTRO_USUARIO, LOGIN, LOGOUT
PERFIL_RECLAMADO, RECLAMACION_APROBADA, RECLAMACION_RECHAZADA
RESERVA_CREADA, RESERVA_CONFIRMADA, RESERVA_CANCELADA, RESERVA_COMPLETADA
CONTRATACION_TELEFONO_CONFIRMADA, CONTRATACION_TELEFONO_RECHAZADA
VALORACION_CREADA, VALORACION_MODERADA
SUSCRIPCION_ACTIVADA, SUSCRIPCION_EXPIRADA
VER_TELEFONO (acción del cliente)
FOTO_BORRADA, PRE_SIGNED_URL_GENERADA
USUARIO_ELIMINADO (anonimización RGPD)
```

### Estructura del registro
```java
AuditLog {
    entidad_tipo: String,     // "profesional", "reserva", etc.
    entidad_id: UUID,
    accion: String,           // constante de la lista anterior
    usuario_id: UUID,         // quien realiza la acción
    ip_hash: String,          // SHA-256 de la IP
    datos_anteriores: JSONB,  // estado previo del recurso
    datos_nuevos: JSONB       // estado nuevo del recurso
}
```

---

## 9. Buenas prácticas de código

### Nomenclatura
- **Código:** inglés (clases, métodos, variables, endpoints)
- **Comentarios y documentación:** español cuando sea necesario
- **Commits:** inglés, formato `feat(TUM-XX): descripción` o `fix(TUM-XX): descripción`
- **Migraciones Flyway:** `V{n}__{descripcion_en_ingles}.sql`

### Backend — reglas
```java
// ✅ Correcto: la lógica va en el service, no en el controller
@Service
@Transactional
public class BookingService {
    public BookingDto createBooking(UUID clienteId, CreateBookingRequest req) {
        // Validar ownership, lógica de negocio, etc.
    }
}

// ❌ Incorrecto: lógica de negocio en el controller
@PostMapping("/bookings")
public ResponseEntity<?> create(@Valid @RequestBody CreateBookingRequest req) {
    // No hacer lógica aquí
}

// ✅ Correcto: nunca acceder al repositorio de otro módulo
// Usar el service del módulo correspondiente
notificationService.notify(userId, tipo, contenido); // ✅
notificacionRepository.save(...); // ❌ si estás en otro módulo

// ✅ Correcto: lanzar excepciones semánticas
throw new ForbiddenException("No tienes permiso para modificar este recurso");
throw new ConflictException("Este perfil ya tiene 3 reclamaciones pendientes");

// ✅ Correcto: DTOs como Java records
public record CreateBookingRequest(
    @NotNull UUID profesionalId,
    @NotNull @Future LocalDateTime fechaServicio,
    UUID servicioId
) {}
```

### Frontend — reglas
```typescript
// ✅ RTK Query para todo el server state
const { data, isLoading, error } = useGetProfessionalQuery(id);

// ❌ No usar fetch manual ni useEffect para llamadas API
useEffect(() => { fetch('/api/...') }, []); // ❌

// ✅ TypeScript estricto. Sin 'any'
interface Profesional {
  id: string;
  nombre: string;
  estado: 'no_reclamado' | 'reclamado' | 'verificado';
}

// ✅ Formularios siempre con React Hook Form + Zod
const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

// ✅ Acceder al estado de sesión desde Redux, no desde localStorage
const { user } = useAppSelector(state => state.auth);
```

### Patrón de validación de ficheros subidos
```java
// Siempre usar Apache Tika para validar MIME real
String mimeType = tika.detect(file.getInputStream());
if (!ALLOWED_MIME_TYPES.contains(mimeType)) {
    throw new ValidationException("Tipo de fichero no permitido");
}
if (file.getSize() > MAX_PHOTO_SIZE_BYTES) {
    throw new ValidationException("El fichero supera el tamaño máximo permitido");
}
```

---

## 10. Design System — tokens de ElGremio

El frontend usa estos tokens definidos en `tailwind.config.js`. Nunca usar colores hardcoded.

### Colores principales
```
primary.DEFAULT:  #1A3C5E  (azul marino — botones primarios, nav, títulos)
primary.light:    #2B5F8C  (hover en botones primarios)
primary.bg:       #E8F0F8  (fondos de secciones destacadas)
secondary.DEFAULT:#E8720C  (ámbar — CTAs secundarios, badges Pro, CTAs)
secondary.light:  #F5A56B  (hover en elementos de acento)
success.DEFAULT:  #2E7D32  (badge verificado, confirmaciones)
warning.DEFAULT:  #E65100  (estados pendientes, avisos)
danger.DEFAULT:   #C62828  (errores, cancelaciones)
neutral.900:      #1C2B3A  (text-primary)
neutral.700:      #546E7A  (text-secondary)
neutral.100:      #F5F7FA  (background)
neutral.50:       #FFFFFF  (surface — tarjetas, paneles)
neutral.border:   #CFD8DC  (separadores, bordes)
```

### Tipografía
- **Familia:** Inter (Google Fonts, sin coste)
- **Escala:** display 48px/700 → h1 32px/700 → h2 24px/600 → body 16px/400 → caption 12px/400

### Componentes base (shadcn/ui + tokens)
- `Button`: variantes primary (azul), secondary (ámbar), ghost, destructive (rojo)
- `Badge`: verified (verde), pro (ámbar), pending (naranja), unverified (gris) — forma pill
- `Card`: sombra `0 2px 8px rgba(26, 60, 94, 0.08)`, border-radius 12px
- `Input`: estados default / focus (borde primary) / error (borde danger) / disabled
- `ProfessionalCard`: avatar, nombre, categoría, ciudad, puntuación, badges, CTA "Ver perfil"

---

## 11. Flujo de trabajo por issue

### Antes de empezar cada tarea
1. Leer el issue completo en Linear (descripción + criterios de aceptación + notas técnicas)
2. Revisar dependencias declaradas en el issue — verificar que están implementadas
3. Revisar el código existente en las capas que vas a modificar
4. Si algo no está claro, **preguntar antes de implementar** — no asumir

### Durante el desarrollo
1. Crear rama con el `gitBranchName` exacto del issue de Linear
2. Seguir el orden: migración Flyway → entidad → repositorio → service → controller → tests → frontend
3. Si la tarea toca `audit_log`, implementar el registro antes de dar por terminada la tarea
4. Si la tarea involucra fotos privadas, verificar que el mecanismo de borrado está contemplado

### Al finalizar cada tarea
Generar un resumen con:
- Ficheros creados y modificados
- Endpoints nuevos o modificados (con método HTTP, ruta y roles requeridos)
- Migraciones Flyway añadidas
- Casos cubiertos en tests
- Decisiones de implementación tomadas (si hubiera ambigüedad resuelta)

### Antes de crear la PR
- `mvn test` en verde (backend)
- `npm run test` en verde (frontend)
- Sin `TODO` sin justificación
- Sin credenciales, URLs de S3 ni secretos hardcodeados en el código
- Migración Flyway numerada correctamente (sin saltos)

---

## 12. Checklist de revisión de código (para el agente QA)

Usar este checklist al revisar cada épica:

### Correctitud funcional
- [ ] Todos los criterios de aceptación del issue están implementados
- [ ] La máquina de estados (si aplica) está completa y sin transiciones ilegales
- [ ] Los ownership checks están presentes antes de cualquier modificación

### Seguridad
- [ ] Endpoints protegidos con los roles correctos (`@PreAuthorize`)
- [ ] No hay datos sensibles expuestos en responses de API (passwords, tokens, s3_key directos)
- [ ] Ficheros subidos validados con Tika (no solo por extensión)
- [ ] Pre-signed URLs con TTL 15 min (no URLs directas de S3 privado)
- [ ] Refresh token en HttpOnly cookie (no en body de respuesta)

### RGPD y privacidad
- [ ] Fotos privadas tienen mecanismo de borrado a 30 días (lifecycle + scheduler)
- [ ] No hay datos personales expuestos innecesariamente
- [ ] Acciones críticas registradas en `audit_log` con `datos_anteriores` y `datos_nuevos`

### Calidad de código
- [ ] Lógica de negocio en el service, no en el controller
- [ ] Los módulos no acceden a repositorios de otros módulos
- [ ] DTOs de entrada son Java records con validaciones `@Valid`
- [ ] MapStruct (no mapping manual) para entidad ↔ DTO
- [ ] Sin `System.out.println` — usar `@Slf4j` y `log.debug/info/warn/error`

### Tests
- [ ] Tests unitarios cubren happy path y casos de error de negocio
- [ ] Tests de integración con Testcontainers (`postgis/postgis:16-3.4`)
- [ ] Control de acceso verificado en tests (rol incorrecto → 403)
- [ ] Tests de ownership (usuario B no puede modificar recursos de usuario A)

### Base de datos
- [ ] Migración Flyway correctamente numerada y sin reversiones manuales
- [ ] Índices añadidos para columnas que se usan en WHERE frecuentes
- [ ] Columnas `GEOGRAPHY` tienen índice GIST

---

## 13. Errores comunes a evitar

```java
// ❌ Guardar el Access Token en localStorage
localStorage.setItem('token', accessToken); // XSS risk

// ❌ Exponer la s3_key directamente en una API response
{ "s3_key": "private/dni/uuid.jpg" } // ❌ — generar pre-signed URL

// ❌ Modificar un recurso sin verificar ownership primero
booking.setEstado(nuevoEstado); // ❌ — verificar antes que el profesional es el dueño

// ❌ Cambiar esquema sin Flyway
// Nunca ejecutar ALTER TABLE manualmente en producción

// ❌ Acceso cruzado de módulos a repositorios
// En BookingService:
valoracionRepository.findBy...; // ❌ — usar ValoracionService

// ❌ Sobreescribir perfiles reclamados con datos del scraper
if (profesional.getEstado() != EstadoProfesional.NO_RECLAMADO) return; // ✅

// ❌ Borrado físico de registros de negocio
profesionalRepository.delete(profesional); // ❌
profesional.setActivo(false); // ✅ borrado lógico
```

---

## 14. Variables de entorno necesarias

```bash
# Base de datos
DB_URL=jdbc:postgresql://localhost:5432/elgremio
DB_USERNAME=...
DB_PASSWORD=...

# JWT
JWT_PRIVATE_KEY=...   # RS256 — desde Secrets Manager
JWT_PUBLIC_KEY=...

# AWS
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=eu-west-1
S3_BUCKET_PUBLIC=elgremio-public
S3_BUCKET_PRIVATE=elgremio-private
S3_BUCKET_DOCS=elgremio-docs
CDN_BASE_URL=https://cdn.elgremio.es

# SendGrid
SENDGRID_API_KEY=...
SENDGRID_FROM_EMAIL=noreply@elgremio.es

# Firebase FCM
FCM_SERVICE_ACCOUNT_JSON=...

# Stripe (v2 — no MVP)
# STRIPE_API_KEY=...
# STRIPE_WEBHOOK_SECRET=...
```

**Regla absoluta:** Ninguna de estas variables va en el código fuente ni en `application.yml` de producción. En local, usar `application-dev.yml` (ignorado por `.gitignore`). En AWS, leer desde Secrets Manager.

---

## 15. Entornos

| Entorno | Trigger | Base de datos | Notas |
|---|---|---|---|
| `dev` | Local | Docker Compose (postgres + postgis) | `application-dev.yml` |
| `staging` | Push a `main` → GitHub Actions automático | RDS staging | Igual a producción en configuración |
| `production` | Push a `release` → aprobación manual | RDS producción | Multi-AZ activable si escala |

### CI/CD (GitHub Actions)
```
Backend: mvn package → docker build → push ECR → ecs update-service
Frontend: npm build → s3 sync → cloudfront invalidation
```

---

*Este documento refleja las decisiones cerradas en la Definición Técnica v2.0 (Mayo 2026) y el Plan Funcional v1.0. Cualquier desviación debe justificarse explícitamente en el código o en el issue de Linear correspondiente.*
