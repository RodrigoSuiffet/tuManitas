import axios, { type AxiosError, type AxiosRequestConfig } from 'axios'
import type { BaseQueryFn } from '@reduxjs/toolkit/query'

const axiosInstance = axios.create({
  baseURL: '/api/v1',
  withCredentials: true,
})

axiosInstance.interceptors.request.use((config) => {
  const token = window.__accessToken
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

let isRefreshing = false
let refreshQueue: Array<(token: string) => void> = []

axiosInstance.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as AxiosRequestConfig & { _retry?: boolean }

    if (error.response?.status === 401 && !originalRequest._retry) {
      if (isRefreshing) {
        return new Promise((resolve) => {
          refreshQueue.push((token) => {
            originalRequest.headers = {
              ...originalRequest.headers,
              Authorization: `Bearer ${token}`,
            }
            resolve(axiosInstance(originalRequest))
          })
        })
      }

      originalRequest._retry = true
      isRefreshing = true

      try {
        const { data } = await axios.post<{ data: { accessToken: string } }>(
          '/api/v1/auth/refresh',
          {},
          { withCredentials: true },
        )
        const newToken = data.data.accessToken
        window.__accessToken = newToken
        refreshQueue.forEach((cb) => cb(newToken))
        refreshQueue = []
        return axiosInstance(originalRequest)
      } catch {
        window.__accessToken = undefined
        return Promise.reject(error)
      } finally {
        isRefreshing = false
      }
    }

    return Promise.reject(error)
  },
)

export const axiosBaseQuery =
  ({
    baseUrl,
  }: {
    baseUrl: string
  }): BaseQueryFn<
    { url: string; method?: string; data?: unknown; params?: unknown },
    unknown,
    unknown
  > =>
  async ({ url, method = 'GET', data, params }) => {
    try {
      const result = await axiosInstance({
        url: `${baseUrl}${url}`,
        method,
        data,
        params,
      })
      const responseData = result.data as { data?: unknown }
      return { data: responseData.data ?? result.data }
    } catch (axiosError) {
      const err = axiosError as AxiosError
      return {
        error: {
          status: err.response?.status,
          data: err.response?.data,
        },
      }
    }
  }

declare global {
  interface Window {
    __accessToken?: string
  }
}
