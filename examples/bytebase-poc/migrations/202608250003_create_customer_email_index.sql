CREATE UNIQUE INDEX customer_email_uq
    ON public.customer (email)
    WHERE email IS NOT NULL;
