import { Navigate, Outlet } from 'react-router-dom'
import type { UserRole } from '../types'

interface ProtectedRouteProps {
  allowedRoles?: UserRole[]
}

export function ProtectedRoute({ allowedRoles: _allowedRoles }: ProtectedRouteProps) {
  const isAuthenticated = false // reemplazar con useAppSelector(state => state.auth) al implementar el módulo auth

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />
  }

  return <Outlet />
}
