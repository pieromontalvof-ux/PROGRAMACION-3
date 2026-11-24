BEGIN;
CREATE TABLE IF NOT EXISTS public.ia_cuota_config (
 id integer PRIMARY KEY CHECK (id=1), activo boolean NOT NULL DEFAULT false,
 diario bigint CHECK(diario>=0), mensual bigint CHECK(mensual>=0),
 global_diario bigint CHECK(global_diario>=0), global_mensual bigint CHECK(global_mensual>=0),
 actualizado_por integer, actualizado_en timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.ia_cuota_config(id,diario,mensual,global_diario,global_mensual)
VALUES(1,200000,2000000,800000,8000000) ON CONFLICT DO NOTHING;
ALTER TABLE public.ia_cuota_config ADD COLUMN IF NOT EXISTS consultas_habilitadas boolean NOT NULL DEFAULT true;
CREATE TABLE IF NOT EXISTS public.ia_cuota_usuario (
 id_usuario integer PRIMARY KEY REFERENCES public.usuario(id_usuario),
 diario bigint CHECK(diario>=0), mensual bigint CHECK(mensual>=0),
 actualizado_por integer NOT NULL, actualizado_en timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.ia_consumo (
 id uuid PRIMARY KEY, id_usuario integer NOT NULL REFERENCES public.usuario(id_usuario),
 id_perfil integer NOT NULL, id_local integer NOT NULL,
 dia date NOT NULL, mes date NOT NULL, modelo varchar(150) NOT NULL,
 reservado bigint NOT NULL CHECK(reservado>=0),
 entrada bigint, salida bigint, total bigint NOT NULL CHECK(total>=0),
 estado varchar(16) NOT NULL CHECK(estado IN ('RESERVADO','CONFIRMADO','INCIERTO','LIBERADO')),
 creado_en timestamptz NOT NULL DEFAULT now(), terminado_en timestamptz
);
CREATE INDEX IF NOT EXISTS ix_ia_consumo_mes_usuario ON public.ia_consumo(mes,id_usuario,dia);
CREATE TABLE IF NOT EXISTS public.ia_cuota_auditoria (
 id bigserial PRIMARY KEY, administrador integer NOT NULL, id_usuario integer,
 anterior jsonb NOT NULL, nuevo jsonb NOT NULL, creado_en timestamptz NOT NULL DEFAULT now()
);
COMMIT;
