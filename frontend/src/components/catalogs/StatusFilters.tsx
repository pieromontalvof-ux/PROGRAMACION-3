type Props<T extends string> = {
  value: T
  onChange: (value: T) => void
  options: readonly { value: T; label: string; count: number }[]
}

export function StatusFilters<T extends string>({ value, onChange, options }: Props<T>) {
  return <nav className="catalog-status-filters" aria-label="Filtrar por estado">
    {options.map(option => <button key={option.value} type="button"
      aria-pressed={value === option.value} onClick={() => onChange(option.value)}>
      {option.label}{' '}<span>{option.count}</span>
    </button>)}
  </nav>
}
