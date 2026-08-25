ALTER TABLE public.customer
    ADD COLUMN email TEXT;

COMMENT ON COLUMN public.customer.email IS 'Optional customer email address';
