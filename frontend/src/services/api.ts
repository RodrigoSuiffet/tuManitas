import { createApi } from '@reduxjs/toolkit/query/react'
import { axiosBaseQuery } from '../lib/axios'

export const api = createApi({
  reducerPath: 'api',
  baseQuery: axiosBaseQuery({ baseUrl: '/api/v1' }),
  tagTypes: [
    'Auth',
    'User',
    'Professional',
    'Booking',
    'Review',
    'Claim',
    'Subscription',
    'Notification',
  ],
  endpoints: () => ({}),
})
