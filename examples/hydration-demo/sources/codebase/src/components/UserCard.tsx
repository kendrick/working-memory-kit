import { User } from "../api/types";

interface UserCardProps {
  user: User;
  onSelect?: (userId: string) => void;
  compact?: boolean;
}

export function UserCard({ user, onSelect, compact = false }: UserCardProps) {
  const handleClick = () => {
    if (onSelect) {
      onSelect(user.id);
    }
  };

  return (
    <div
      className={`rounded-lg border border-slate-200 bg-white p-4 hover:border-slate-300 ${
        compact ? "text-sm" : ""
      }`}
      onClick={handleClick}
      role={onSelect ? "button" : undefined}
    >
      <div className="font-medium text-slate-900">{user.displayName}</div>
      <div className="text-slate-500">{user.email}</div>
      <div className="mt-2">
        <span className="inline-flex items-center rounded-full bg-slate-100 px-2 py-1 text-xs font-medium text-slate-700">
          {user.role}
        </span>
      </div>
    </div>
  );
}
