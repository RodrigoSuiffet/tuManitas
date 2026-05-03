export type UserRole =
  | 'ROLE_CLIENT'
  | 'ROLE_PROFESSIONAL'
  | 'ROLE_COMPANY_ADMIN'
  | 'ROLE_BACKOFFICE'
  | 'ROLE_ADMIN'

export type ProfessionalStatus = 'no_reclamado' | 'reclamado' | 'verificado'

export type BookingStatus =
  | 'pendiente'
  | 'confirmada'
  | 'completada'
  | 'cancelada'
  | 'rechazada'

export type BookingChannel = 'app' | 'telefono'

export type ClaimStatus =
  | 'pendiente'
  | 'aprobada'
  | 'rechazada'
  | 'cancelada'
  | 'bloqueada'

export interface ApiResponse<T> {
  success: boolean
  data: T | null
  message: string | null
}

export interface PaginatedResponse<T> {
  content: T[]
  totalElements: number
  totalPages: number
  number: number
  size: number
}

export interface User {
  id: string
  email: string
  nombre: string
  apellidos: string
  telefono: string | null
  roles: UserRole[]
  createdAt: string
}

export interface Professional {
  id: string
  nombre: string
  apellidos: string
  telefono: string
  descripcion: string | null
  categoriaId: string
  categoriaNombre: string
  ciudad: string
  provincia: string
  estado: ProfessionalStatus
  puntuacionMedia: number
  totalValoraciones: number
  tieneSubscripcion: boolean
  lat: number | null
  lng: number | null
  fotosPortfolio: string[]
}
