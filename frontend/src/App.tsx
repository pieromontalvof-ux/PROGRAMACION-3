import { lazy, Suspense } from 'react'
const DiagnosticsPage = lazy(() => import('./pages/DiagnosticsPage').then(module => ({ default: module.DiagnosticsPage })))
const SalesJournalPage = lazy(() => import('./features/salonPayments/SalesJournalPage').then(module => ({ default: module.SalesJournalPage })))
const AssistantPage = lazy(() => import('./features/asistenteIA/AssistantPage').then(module => ({ default: module.AssistantPage })))
const AgentAdminPage = lazy(() => import('./features/asistenteIA/AgentAdminPage').then(module => ({ default: module.AgentAdminPage })))
const TokenLimitsPage = lazy(() => import('./features/asistenteIA/TokenLimitsPage').then(module => ({ default: module.TokenLimitsPage })))
const SalonLayoutPage = lazy(() => import('./pages/SalonLayoutPage').then(module => ({ default: module.SalonLayoutPage })))
const SalonOrderPage = lazy(() => import('./pages/SalonOrderPage').then(module => ({ default: module.SalonOrderPage })))
const SalonPaymentPage = lazy(() => import('./features/salonPayments/SalonPaymentPage').then(module => ({ default: module.SalonPaymentPage })))
const SalonPage = lazy(() => import('./pages/SalonPage').then(module => ({ default: module.SalonPage })))
const ActivityPage = lazy(() => import('./pages/ActivityPage').then(module => ({ default: module.ActivityPage })))
const MovementTrackingPage = lazy(() => import('./pages/MovementTrackingPage').then(module => ({ default: module.MovementTrackingPage })))
import {
  Navigate,
  Route,
  Routes,
} from 'react-router-dom'
const SuppliersPage = lazy(() => import('./pages/SuppliersPage').then(module => ({ default: module.SuppliersPage })))
import { ProtectedRoute } from './components/ProtectedRoute'
import { MainLayout } from './components/layout/MainLayout'
const ProductsPage = lazy(() => import('./pages/ProductsPage').then(module => ({ default: module.ProductsPage })))
const HomePage = lazy(() => import('./pages/HomePage').then(module => ({ default: module.HomePage })))
const OperationalPage = lazy(() => import('./features/inventoryOperations/OperationalPage').then(module => ({ default: module.OperationalPage })))
const LoginPage = lazy(() => import('./pages/LoginPage'))
const ModulePlaceholderPage = lazy(() => import('./pages/ModulePlaceholderPage').then(module => ({ default: module.ModulePlaceholderPage })))
const StockPage = lazy(() => import('./pages/StockPage').then(module => ({ default: module.StockPage })))
const StockLimitsPage = lazy(() => import('./pages/StockLimitsPage').then(module => ({ default: module.StockLimitsPage })))
const ProductCategoriesPage = lazy(() => import('./pages/ProductCategoriesPage').then(module => ({ default: module.ProductCategoriesPage })))
const MenuCategoriesPage = lazy(() => import('./pages/MenuCategoriesPage').then(module => ({ default: module.MenuCategoriesPage })))

const SubproductsPage = lazy(() => import('./pages/SubproductsPage').then(module => ({ default: module.SubproductsPage })))

const SalesPresentationsPage = lazy(() => import('./pages/SalesPresentationsPage').then(module => ({ default: module.SalesPresentationsPage })))
const TablewarePage = lazy(() => import('./pages/TablewarePage').then(module => ({ default: module.TablewarePage })))

const PromotionsPage = lazy(() => import('./pages/PromotionsPage').then(module => ({ default: module.PromotionsPage })))


const RegisterMovementPage = lazy(() => import('./pages/RegisterMovementPage').then(module => ({ default: module.RegisterMovementPage })))

const PendingReceiptsPage = lazy(() => import('./pages/PendingReceiptsPage').then(module => ({ default: module.PendingReceiptsPage })))

const PurchaseOrderPage = lazy(() => import('./pages/PurchaseOrderPage').then(module => ({ default: module.PurchaseOrderPage })))

const UsersPage = lazy(() => import('./pages/UsersPage').then(module => ({ default: module.UsersPage })))
const StoresPage = lazy(() => import('./pages/StoresPage').then(module => ({ default: module.StoresPage })))
const RecipesPage = lazy(() => import('./pages/RecipesPage').then(module => ({ default: module.RecipesPage })))

const PurchaseOrderHistoryPage = lazy(() => import('./pages/PurchaseOrderHistoryPage').then(module => ({ default: module.PurchaseOrderHistoryPage })))
const ReceptionHistoryPage = lazy(() => import('./pages/ReceptionHistoryPage').then(module => ({ default: module.ReceptionHistoryPage })))

function App() {
  return (
    <Suspense fallback={<p role="status">Cargando pantalla...</p>}><Routes>
      <Route path="/salon" element={<SalonPage />} />
      <Route path="/salon/ventas" element={<SalesJournalPage />} />
      <Route path="/salon/mesa/:mesa" element={<SalonOrderPage />} />
      <Route path="/salon/mesa/:mesa/pagar" element={<SalonPaymentPage />} />
      <Route path="/salon/comprobante/:id" element={<SalonPaymentPage />} />
      <Route
        path="/"
        element={<Navigate to="/login" replace />}
      />

      <Route
        path="/login"
        element={<LoginPage />}
      />

      <Route
        path="/home"
        element={
          <ProtectedRoute>
            <MainLayout />
          </ProtectedRoute>
        }
      >
        <Route
          index
          element={<HomePage />}
        />

        <Route
          path="stock"
          element={<StockPage />}
        />
        <Route path="asistente-ia" element={<AssistantPage />} />
        <Route path="asistente-ia/agentes" element={<AgentAdminPage mode="mapa" />} />
        <Route path="asistente-ia/archivos" element={<AgentAdminPage mode="archivos" />} />
        <Route path="asistente-ia/permisos" element={<AgentAdminPage mode="permisos" />} />
        <Route path="asistente-ia/limites" element={<TokenLimitsPage />} />
        <Route path="tiendas" element={<StoresPage />} />
        <Route path="opciones-salon" element={<SalonLayoutPage />} />
        <Route path="limites-stock" element={<StockLimitsPage />} />

        <Route
          path="productos"
          element={<ProductsPage />}
        />

        <Route
          path="categorias-productos"
          element={<ProductCategoriesPage />}
        />

        <Route
          path="proveedores"
          element={<SuppliersPage />}
        />

        <Route
          path="carta/categorias"
          element={<MenuCategoriesPage />}
        />

        <Route
          path="carta/presentaciones"
          element={<SalesPresentationsPage />}
        />

        <Route
          path="subproductos"
          element={<SubproductsPage />}
        />

        <Route
          path="grupos-salsa"
          element={<Navigate to="/home/recetas" replace />}
        />

        <Route
          path="recetas"
          element={<RecipesPage />}
        />

        <Route
          path="carta/menajes"
          element={<TablewarePage />}
        />

        <Route
          path="inventarios/realizar"
          element={<Navigate to="/home/inventarios/conteos" replace />}
        />

        <Route
          path="promociones"
          element={<PromotionsPage />}
        />

        <Route
          path="inventarios/revisar"
          element={<Navigate to="/home/inventarios/conteos" replace />}
        />

        <Route
          path="recepciones/pendientes"
          element={<PendingReceiptsPage />}
        />
        <Route path="inventarios/dia" element={<OperationalPage section="day" />} />
        <Route path="inventarios/mix" element={<OperationalPage section="mix" />} />
        <Route path="inventarios/conteos" element={<OperationalPage section="counts" />} />

        <Route
          path="movimientos/seguimiento" element={<MovementTrackingPage />} />
        <Route
          path="movimientos/registrar"
          element={<RegisterMovementPage />}
        />

        <Route
          path="ordenes-compra/crear"
          element={<PurchaseOrderPage />}
        />

        <Route
          path="actividades" element={<ActivityPage />} />
        <Route path="diagnostico" element={<DiagnosticsPage />} />
        <Route
          path="usuarios"
          element={<UsersPage />}
        />

        <Route
          path="ordenes-compra/historial"
          element={<PurchaseOrderHistoryPage />}
        />

        <Route
          path="recepciones/historial"
          element={<ReceptionHistoryPage />}
        />

        <Route
          path="*"
          element={<ModulePlaceholderPage />}
        />
      </Route>

      <Route
        path="*"
        element={<Navigate to="/home" replace />}
      />
    </Routes></Suspense>
  )
}

export default App
