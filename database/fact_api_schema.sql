--
-- PostgreSQL database dump
--

\restrict P4TbVCQwmiWW9z4u4UJjBmioKsAFqScHICqJzZYwHFewSdMEa7lu3xHny2Ai5wh

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: barbarito_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.barbarito_documents (
    id uuid NOT NULL,
    company_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    origin character varying(10) NOT NULL,
    source_reference character varying(40) NOT NULL,
    native_id bigint,
    native_type character varying(20),
    number character varying(80) NOT NULL,
    payload_hash character varying(64) NOT NULL,
    payload json NOT NULL,
    state character varying(30) DEFAULT 'DEMO_GENERADO'::character varying NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: barbarito_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.barbarito_files (
    id bigint NOT NULL,
    document_id uuid NOT NULL,
    format character varying(10) NOT NULL,
    path character varying(255) NOT NULL,
    sha256 character varying(64) NOT NULL,
    bytes integer NOT NULL
);


--
-- Name: barbarito_files_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.barbarito_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: barbarito_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.barbarito_files_id_seq OWNED BY public.barbarito_files.id;


--
-- Name: boletas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.boletas (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    client_id bigint NOT NULL,
    tipo_documento character varying(2) DEFAULT '03'::character varying NOT NULL,
    serie character varying(4) NOT NULL,
    correlativo character varying(8) NOT NULL,
    numero_completo character varying(15) NOT NULL,
    fecha_emision date NOT NULL,
    ubl_version character varying(3) DEFAULT '2.1'::character varying NOT NULL,
    tipo_operacion character varying(4) DEFAULT '0101'::character varying NOT NULL,
    moneda character varying(3) DEFAULT 'PEN'::character varying NOT NULL,
    valor_venta numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_gravadas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_exoneradas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_inafectas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_gratuitas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_igv numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_isc numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_icbper numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    total_impuestos numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    sub_total numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_imp_venta numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    detalles json NOT NULL,
    leyendas json,
    datos_adicionales json,
    xml_path character varying(255),
    cdr_path character varying(255),
    pdf_path character varying(255),
    estado_sunat character varying(20) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    respuesta_sunat text,
    codigo_hash character varying(255),
    usuario_creacion character varying(255),
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    mto_base_ivap numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_ivap numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_igv_gratuitas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    consulta_cpe_estado character varying(2),
    consulta_cpe_respuesta json,
    consulta_cpe_fecha timestamp(0) without time zone,
    metodo_envio character varying(20) DEFAULT 'individual'::character varying NOT NULL,
    daily_summary_id bigint
);


--
-- Name: COLUMN boletas.mto_base_ivap; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.boletas.mto_base_ivap IS 'Base imponible IVAP';


--
-- Name: COLUMN boletas.mto_ivap; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.boletas.mto_ivap IS 'Monto IVAP';


--
-- Name: boletas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.boletas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: boletas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.boletas_id_seq OWNED BY public.boletas.id;


--
-- Name: branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branches (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(255) NOT NULL,
    direccion character varying(255) NOT NULL,
    ubigeo character varying(6) NOT NULL,
    distrito character varying(255) NOT NULL,
    provincia character varying(255) NOT NULL,
    departamento character varying(255) NOT NULL,
    telefono character varying(255),
    email character varying(255),
    series_factura json,
    series_boleta json,
    series_nota_credito json,
    series_nota_debito json,
    series_guia_remision json,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: branches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.branches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: branches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.branches_id_seq OWNED BY public.branches.id;


--
-- Name: cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cache (
    key character varying(255) NOT NULL,
    value text NOT NULL,
    expiration integer NOT NULL
);


--
-- Name: cache_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cache_locks (
    key character varying(255) NOT NULL,
    owner character varying(255) NOT NULL,
    expiration integer NOT NULL
);


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clients (
    id bigint NOT NULL,
    tipo_documento character varying(1) NOT NULL,
    numero_documento character varying(15) NOT NULL,
    razon_social character varying(255) NOT NULL,
    nombre_comercial character varying(255),
    direccion character varying(255),
    ubigeo character varying(6),
    distrito character varying(255),
    provincia character varying(255),
    departamento character varying(255),
    telefono character varying(255),
    email character varying(255),
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    company_id bigint,
    barbarito_customer boolean DEFAULT false NOT NULL,
    barbarito_supplier boolean DEFAULT false NOT NULL
);


--
-- Name: clients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clients_id_seq OWNED BY public.clients.id;


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id bigint NOT NULL,
    ruc character varying(11) NOT NULL,
    razon_social character varying(255) NOT NULL,
    nombre_comercial character varying(255),
    direccion character varying(255) NOT NULL,
    ubigeo character varying(6) NOT NULL,
    distrito character varying(255) NOT NULL,
    provincia character varying(255) NOT NULL,
    departamento character varying(255) NOT NULL,
    telefono character varying(255),
    email character varying(255),
    web character varying(255),
    usuario_sol character varying(255) NOT NULL,
    clave_sol character varying(255) NOT NULL,
    certificado_pem text,
    certificado_password character varying(255),
    endpoint_beta character varying(255) NOT NULL,
    endpoint_produccion character varying(255) NOT NULL,
    modo_produccion boolean DEFAULT false NOT NULL,
    logo_path character varying(255),
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    api_sunat_client_id character varying(255),
    api_sunat_client_secret character varying(255),
    api_sunat_endpoint_beta character varying(255) DEFAULT 'https://api-beta.sunat.gob.pe'::character varying,
    api_sunat_endpoint_produccion character varying(255) DEFAULT 'https://api.sunat.gob.pe'::character varying
);


--
-- Name: companies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.companies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: companies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.companies_id_seq OWNED BY public.companies.id;


--
-- Name: company_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_configurations (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    config_type character varying(255) NOT NULL,
    environment character varying(255) DEFAULT 'general'::character varying NOT NULL,
    service_type character varying(255),
    config_data json NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    description character varying(255),
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    CONSTRAINT company_configurations_config_type_check CHECK (((config_type)::text = ANY ((ARRAY['tax_settings'::character varying, 'invoice_settings'::character varying, 'gre_settings'::character varying, 'document_settings'::character varying])::text[]))),
    CONSTRAINT company_configurations_environment_check CHECK (((environment)::text = ANY ((ARRAY['general'::character varying, 'beta'::character varying, 'produccion'::character varying])::text[]))),
    CONSTRAINT company_configurations_service_type_check CHECK (((service_type)::text = ANY ((ARRAY['general'::character varying, 'facturacion'::character varying, 'guias_remision'::character varying, 'resumenes_diarios'::character varying, 'comunicaciones_baja'::character varying, 'retenciones'::character varying])::text[])))
);


--
-- Name: company_configurations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.company_configurations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: company_configurations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.company_configurations_id_seq OWNED BY public.company_configurations.id;


--
-- Name: correlatives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.correlatives (
    id bigint NOT NULL,
    branch_id bigint NOT NULL,
    tipo_documento character varying(2) NOT NULL,
    serie character varying(4) NOT NULL,
    correlativo_actual integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: correlatives_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.correlatives_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: correlatives_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.correlatives_id_seq OWNED BY public.correlatives.id;


--
-- Name: failed_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.failed_jobs (
    id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    connection text NOT NULL,
    queue text NOT NULL,
    payload text NOT NULL,
    exception text NOT NULL,
    failed_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: failed_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.failed_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: failed_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.failed_jobs_id_seq OWNED BY public.failed_jobs.id;


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    client_id bigint NOT NULL,
    tipo_documento character varying(2) DEFAULT '01'::character varying NOT NULL,
    serie character varying(4) NOT NULL,
    correlativo character varying(8) NOT NULL,
    numero_completo character varying(15) NOT NULL,
    fecha_emision date NOT NULL,
    fecha_vencimiento date,
    ubl_version character varying(3) DEFAULT '2.1'::character varying NOT NULL,
    tipo_operacion character varying(4) DEFAULT '0101'::character varying NOT NULL,
    moneda character varying(3) DEFAULT 'PEN'::character varying NOT NULL,
    forma_pago_tipo character varying(20) DEFAULT 'Contado'::character varying NOT NULL,
    forma_pago_cuotas json,
    valor_venta numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_gravadas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_exoneradas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_inafectas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_exportacion numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_oper_gratuitas numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_igv_gratuitas numeric(10,2) DEFAULT '0'::numeric NOT NULL,
    mto_igv numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_isc numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_icbper numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_otros_tributos numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_detraccion numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_percepcion numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_retencion numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    total_impuestos numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    sub_total numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_imp_venta numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_anticipos numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    detalles json NOT NULL,
    leyendas json,
    guias json,
    documentos_relacionados json,
    detraccion json,
    percepcion json,
    retencion json,
    datos_adicionales json,
    xml_path character varying(255),
    cdr_path character varying(255),
    pdf_path character varying(255),
    estado_sunat character varying(20) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    respuesta_sunat text,
    codigo_hash character varying(255),
    usuario_creacion character varying(255),
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    mto_base_ivap numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mto_ivap numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    consulta_cpe_estado character varying(2),
    consulta_cpe_respuesta json,
    consulta_cpe_fecha timestamp(0) without time zone
);


--
-- Name: COLUMN invoices.mto_base_ivap; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.mto_base_ivap IS 'Base imponible IVAP';


--
-- Name: COLUMN invoices.mto_ivap; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.mto_ivap IS 'Monto IVAP';


--
-- Name: invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.invoices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.invoices_id_seq OWNED BY public.invoices.id;


--
-- Name: job_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_batches (
    id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    total_jobs integer NOT NULL,
    pending_jobs integer NOT NULL,
    failed_jobs integer NOT NULL,
    failed_job_ids text NOT NULL,
    options text,
    cancelled_at integer,
    created_at integer NOT NULL,
    finished_at integer
);


--
-- Name: jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jobs (
    id bigint NOT NULL,
    queue character varying(255) NOT NULL,
    payload text NOT NULL,
    attempts smallint NOT NULL,
    reserved_at integer,
    available_at integer NOT NULL,
    created_at integer NOT NULL
);


--
-- Name: jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jobs_id_seq OWNED BY public.jobs.id;


--
-- Name: migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    migration character varying(255) NOT NULL,
    batch integer NOT NULL
);


--
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- Name: password_reset_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_reset_tokens (
    email character varying(255) NOT NULL,
    token character varying(255) NOT NULL,
    created_at timestamp(0) without time zone
);


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    description text,
    category character varying(255) DEFAULT 'general'::character varying NOT NULL,
    is_system boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.permissions_id_seq OWNED BY public.permissions.id;


--
-- Name: personal_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.personal_access_tokens (
    id bigint NOT NULL,
    tokenable_type character varying(255) NOT NULL,
    tokenable_id bigint NOT NULL,
    name text NOT NULL,
    token character varying(64) NOT NULL,
    abilities text,
    last_used_at timestamp(0) without time zone,
    expires_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: personal_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.personal_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: personal_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.personal_access_tokens_id_seq OWNED BY public.personal_access_tokens.id;


--
-- Name: role_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permission (
    id bigint NOT NULL,
    role_id bigint NOT NULL,
    permission_id bigint NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: role_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.role_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: role_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.role_permission_id_seq OWNED BY public.role_permission.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    description text,
    permissions json,
    is_system boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id character varying(255) NOT NULL,
    user_id bigint,
    ip_address character varying(45),
    user_agent text,
    payload text NOT NULL,
    last_activity integer NOT NULL
);


--
-- Name: ubi_distritos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ubi_distritos (
    id character varying(6) NOT NULL,
    nombre character varying(255) DEFAULT ''::character varying NOT NULL,
    info_busqueda character varying(255) DEFAULT ''::character varying NOT NULL,
    provincia_id character varying(6) DEFAULT ''::character varying NOT NULL,
    region_id character varying(6) DEFAULT ''::character varying NOT NULL
);


--
-- Name: ubi_provincias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ubi_provincias (
    id character varying(6) NOT NULL,
    nombre character varying(255) DEFAULT ''::character varying NOT NULL,
    region_id character varying(6) DEFAULT ''::character varying NOT NULL
);


--
-- Name: ubi_regiones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ubi_regiones (
    id character varying(6) NOT NULL,
    nombre character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    email_verified_at timestamp(0) without time zone,
    password character varying(255) NOT NULL,
    remember_token character varying(100),
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    role_id bigint,
    company_id bigint,
    user_type character varying(255) DEFAULT 'user'::character varying NOT NULL,
    allowed_ips json,
    permissions json,
    restrictions json,
    last_login_at timestamp(0) without time zone,
    last_login_ip character varying(255),
    failed_login_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp(0) without time zone,
    active boolean DEFAULT true NOT NULL,
    force_password_change boolean DEFAULT false NOT NULL,
    password_changed_at timestamp(0) without time zone,
    metadata json
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: barbarito_files id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barbarito_files ALTER COLUMN id SET DEFAULT nextval('public.barbarito_files_id_seq'::regclass);


--
-- Name: boletas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boletas ALTER COLUMN id SET DEFAULT nextval('public.boletas_id_seq'::regclass);


--
-- Name: branches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches ALTER COLUMN id SET DEFAULT nextval('public.branches_id_seq'::regclass);


--
-- Name: clients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients ALTER COLUMN id SET DEFAULT nextval('public.clients_id_seq'::regclass);


--
-- Name: companies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies ALTER COLUMN id SET DEFAULT nextval('public.companies_id_seq'::regclass);


--
-- Name: company_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_configurations ALTER COLUMN id SET DEFAULT nextval('public.company_configurations_id_seq'::regclass);


--
-- Name: correlatives id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correlatives ALTER COLUMN id SET DEFAULT nextval('public.correlatives_id_seq'::regclass);


--
-- Name: failed_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.failed_jobs ALTER COLUMN id SET DEFAULT nextval('public.failed_jobs_id_seq'::regclass);


--
-- Name: invoices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices ALTER COLUMN id SET DEFAULT nextval('public.invoices_id_seq'::regclass);


--
-- Name: jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs ALTER COLUMN id SET DEFAULT nextval('public.jobs_id_seq'::regclass);


--
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- Name: permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions ALTER COLUMN id SET DEFAULT nextval('public.permissions_id_seq'::regclass);


--
-- Name: personal_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.personal_access_tokens_id_seq'::regclass);


--
-- Name: role_permission id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permission ALTER COLUMN id SET DEFAULT nextval('public.role_permission_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: barbarito_documents barbarito_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barbarito_documents
    ADD CONSTRAINT barbarito_documents_pkey PRIMARY KEY (id);


--
-- Name: barbarito_files barbarito_files_document_id_format_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barbarito_files
    ADD CONSTRAINT barbarito_files_document_id_format_unique UNIQUE (document_id, format);


--
-- Name: barbarito_files barbarito_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barbarito_files
    ADD CONSTRAINT barbarito_files_pkey PRIMARY KEY (id);


--
-- Name: boletas boletas_company_id_serie_correlativo_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boletas
    ADD CONSTRAINT boletas_company_id_serie_correlativo_unique UNIQUE (company_id, serie, correlativo);


--
-- Name: boletas boletas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boletas
    ADD CONSTRAINT boletas_pkey PRIMARY KEY (id);


--
-- Name: branches branches_company_id_codigo_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_company_id_codigo_unique UNIQUE (company_id, codigo);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: cache_locks cache_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cache_locks
    ADD CONSTRAINT cache_locks_pkey PRIMARY KEY (key);


--
-- Name: cache cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cache
    ADD CONSTRAINT cache_pkey PRIMARY KEY (key);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: clients clients_tipo_documento_numero_documento_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_tipo_documento_numero_documento_unique UNIQUE (tipo_documento, numero_documento);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: companies companies_ruc_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_ruc_unique UNIQUE (ruc);


--
-- Name: company_configurations company_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_configurations
    ADD CONSTRAINT company_configurations_pkey PRIMARY KEY (id);


--
-- Name: correlatives correlatives_branch_id_tipo_documento_serie_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correlatives
    ADD CONSTRAINT correlatives_branch_id_tipo_documento_serie_unique UNIQUE (branch_id, tipo_documento, serie);


--
-- Name: correlatives correlatives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correlatives
    ADD CONSTRAINT correlatives_pkey PRIMARY KEY (id);


--
-- Name: failed_jobs failed_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.failed_jobs
    ADD CONSTRAINT failed_jobs_pkey PRIMARY KEY (id);


--
-- Name: failed_jobs failed_jobs_uuid_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.failed_jobs
    ADD CONSTRAINT failed_jobs_uuid_unique UNIQUE (uuid);


--
-- Name: invoices invoices_company_id_serie_correlativo_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_company_id_serie_correlativo_unique UNIQUE (company_id, serie, correlativo);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: job_batches job_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_batches
    ADD CONSTRAINT job_batches_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: password_reset_tokens password_reset_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_pkey PRIMARY KEY (email);


--
-- Name: permissions permissions_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_name_unique UNIQUE (name);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: personal_access_tokens personal_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_tokens
    ADD CONSTRAINT personal_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: personal_access_tokens personal_access_tokens_token_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_tokens
    ADD CONSTRAINT personal_access_tokens_token_unique UNIQUE (token);


--
-- Name: role_permission role_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permission
    ADD CONSTRAINT role_permission_pkey PRIMARY KEY (id);


--
-- Name: role_permission role_permission_role_id_permission_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permission
    ADD CONSTRAINT role_permission_role_id_permission_id_unique UNIQUE (role_id, permission_id);


--
-- Name: roles roles_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_unique UNIQUE (name);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: ubi_distritos ubi_distritos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ubi_distritos
    ADD CONSTRAINT ubi_distritos_pkey PRIMARY KEY (id);


--
-- Name: ubi_provincias ubi_provincias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ubi_provincias
    ADD CONSTRAINT ubi_provincias_pkey PRIMARY KEY (id);


--
-- Name: ubi_regiones ubi_regiones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ubi_regiones
    ADD CONSTRAINT ubi_regiones_pkey PRIMARY KEY (id);


--
-- Name: company_configurations unique_company_config; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_configurations
    ADD CONSTRAINT unique_company_config UNIQUE (company_id, config_type, environment, service_type);


--
-- Name: users users_email_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_unique UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: boletas_company_id_branch_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX boletas_company_id_branch_id_index ON public.boletas USING btree (company_id, branch_id);


--
-- Name: boletas_consulta_cpe_estado_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX boletas_consulta_cpe_estado_index ON public.boletas USING btree (consulta_cpe_estado);


--
-- Name: boletas_consulta_cpe_fecha_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX boletas_consulta_cpe_fecha_index ON public.boletas USING btree (consulta_cpe_fecha);


--
-- Name: boletas_daily_summary_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX boletas_daily_summary_id_index ON public.boletas USING btree (daily_summary_id);


--
-- Name: boletas_estado_sunat_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX boletas_estado_sunat_index ON public.boletas USING btree (estado_sunat);


--
-- Name: boletas_fecha_emision_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX boletas_fecha_emision_index ON public.boletas USING btree (fecha_emision);


--
-- Name: company_configurations_company_id_config_type_environment_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_configurations_company_id_config_type_environment_index ON public.company_configurations USING btree (company_id, config_type, environment);


--
-- Name: company_configurations_company_id_config_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_configurations_company_id_config_type_index ON public.company_configurations USING btree (company_id, config_type);


--
-- Name: company_configurations_company_id_environment_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_configurations_company_id_environment_index ON public.company_configurations USING btree (company_id, environment);


--
-- Name: company_configurations_company_id_service_type_environment_inde; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_configurations_company_id_service_type_environment_inde ON public.company_configurations USING btree (company_id, service_type, environment);


--
-- Name: correlatives_branch_id_tipo_documento_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX correlatives_branch_id_tipo_documento_index ON public.correlatives USING btree (branch_id, tipo_documento);


--
-- Name: invoices_company_id_branch_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_company_id_branch_id_index ON public.invoices USING btree (company_id, branch_id);


--
-- Name: invoices_consulta_cpe_estado_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_consulta_cpe_estado_index ON public.invoices USING btree (consulta_cpe_estado);


--
-- Name: invoices_consulta_cpe_fecha_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_consulta_cpe_fecha_index ON public.invoices USING btree (consulta_cpe_fecha);


--
-- Name: invoices_estado_sunat_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_estado_sunat_index ON public.invoices USING btree (estado_sunat);


--
-- Name: invoices_fecha_emision_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_fecha_emision_index ON public.invoices USING btree (fecha_emision);


--
-- Name: jobs_queue_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX jobs_queue_index ON public.jobs USING btree (queue);


--
-- Name: permissions_category_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX permissions_category_active_index ON public.permissions USING btree (category, active);


--
-- Name: permissions_name_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX permissions_name_active_index ON public.permissions USING btree (name, active);


--
-- Name: personal_access_tokens_expires_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX personal_access_tokens_expires_at_index ON public.personal_access_tokens USING btree (expires_at);


--
-- Name: personal_access_tokens_tokenable_type_tokenable_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX personal_access_tokens_tokenable_type_tokenable_id_index ON public.personal_access_tokens USING btree (tokenable_type, tokenable_id);


--
-- Name: roles_name_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX roles_name_active_index ON public.roles USING btree (name, active);


--
-- Name: sessions_last_activity_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessions_last_activity_index ON public.sessions USING btree (last_activity);


--
-- Name: sessions_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessions_user_id_index ON public.sessions USING btree (user_id);


--
-- Name: users_company_id_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_company_id_active_index ON public.users USING btree (company_id, active);


--
-- Name: users_last_login_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_last_login_at_index ON public.users USING btree (last_login_at);


--
-- Name: users_user_type_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_user_type_active_index ON public.users USING btree (user_type, active);


--
-- Name: boletas boletas_branch_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boletas
    ADD CONSTRAINT boletas_branch_id_foreign FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: boletas boletas_client_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boletas
    ADD CONSTRAINT boletas_client_id_foreign FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: boletas boletas_company_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boletas
    ADD CONSTRAINT boletas_company_id_foreign FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: branches branches_company_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_company_id_foreign FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: clients clients_company_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_company_id_foreign FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_configurations company_configurations_company_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_configurations
    ADD CONSTRAINT company_configurations_company_id_foreign FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: correlatives correlatives_branch_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correlatives
    ADD CONSTRAINT correlatives_branch_id_foreign FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: invoices invoices_branch_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_branch_id_foreign FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: invoices invoices_client_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_client_id_foreign FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: invoices invoices_company_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_company_id_foreign FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: role_permission role_permission_permission_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permission
    ADD CONSTRAINT role_permission_permission_id_foreign FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE CASCADE;


--
-- Name: role_permission role_permission_role_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permission
    ADD CONSTRAINT role_permission_role_id_foreign FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: ubi_distritos ubi_distritos_provincia_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ubi_distritos
    ADD CONSTRAINT ubi_distritos_provincia_id_foreign FOREIGN KEY (provincia_id) REFERENCES public.ubi_provincias(id);


--
-- Name: ubi_distritos ubi_distritos_region_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ubi_distritos
    ADD CONSTRAINT ubi_distritos_region_id_foreign FOREIGN KEY (region_id) REFERENCES public.ubi_regiones(id);


--
-- Name: ubi_provincias ubi_provincias_region_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ubi_provincias
    ADD CONSTRAINT ubi_provincias_region_id_foreign FOREIGN KEY (region_id) REFERENCES public.ubi_regiones(id);


--
-- Name: users users_company_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_company_id_foreign FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: users users_role_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_foreign FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict P4TbVCQwmiWW9z4u4UJjBmioKsAFqScHICqJzZYwHFewSdMEa7lu3xHny2Ai5wh
