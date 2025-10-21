import { z } from 'zod';

const isoDateRegex = /^\d{4}-\d{2}-\d{2}$/;
const timeRegex = /^([01]\d|2[0-3]):([0-5]\d)$/;
const phoneRegex = /^\+?[0-9\s-]{8,20}$/;

const stringField = z.string().trim().min(1);

export const CreateTripSchema = z.object({
  fromCity: stringField,
  toCity: stringField,
  date: z
    .string()
    .trim()
    .regex(isoDateRegex, 'date must be in YYYY-MM-DD format'),
  time: z
    .string()
    .trim()
    .regex(timeRegex, 'time must be in HH:mm format'),
  price: z.number().positive('price must be a positive number'),
  carModel: stringField,
  carColor: stringField,
  phoneNumber: z
    .string()
    .trim()
    .regex(phoneRegex, 'phoneNumber must be a valid phone number'),
  notes: z.string().trim().optional(),
});

export const UpdateTripSchema = CreateTripSchema.partial().refine(
  (value) => Object.keys(value).length > 0,
  'At least one field must be provided to update',
);

export type CreateTripInput = z.infer<typeof CreateTripSchema>;
export type UpdateTripInput = z.infer<typeof UpdateTripSchema>;
