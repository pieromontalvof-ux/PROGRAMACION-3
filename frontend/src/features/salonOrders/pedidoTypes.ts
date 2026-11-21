export interface Opcion {id:number;nombre:string;cantidad?:number;unidad?:string}
export interface Producto {id:number;nombre:string;precio:number;id_categoria:number;categoria:string;grupo:{maximo:number;repetir:boolean;opciones:Opcion[]}|null;reponible?:boolean}
export interface GrupoPromocion {id:number;cantidad:number;repetir:boolean;opciones:Producto[]}
export interface Promocion {id:number;nombre:string;precio:number;grupos:GrupoPromocion[]}
export interface SeleccionPromocion {id_grupo:number;id_presentacion:number;nombre:string;reponible:boolean;grupo:Producto['grupo'];opciones:Opcion[]}
export interface SeleccionBorrador extends SeleccionPromocion {clave:string}
export interface Linea {id_presentacion:number|null;id_promocion?:number|null;selecciones_promocion?:SeleccionPromocion[];cantidad_reposiciones?:number;id_barra_libre?:number|null;barra_nombre?:string|null;nombre:string;precio:number;cantidad:number;comentario:string;opciones:Opcion[];enviada:boolean;ids_lineas?:number[]}
export interface Pedido {puede_editar:boolean;mesa:string;version:number;id_borrador:number|null;lineas:Linea[];total:number}
export interface Carta {productos:Producto[];promociones:Promocion[]}
export interface Sesion {local:string;usuario:string;perfil:number}
