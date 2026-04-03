#include <octave/defun-dld.h>
#include <octave/oct.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <complex>
#include <limits>
#include <string>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace {

std::string to_lower_copy(const std::string& s) {
  std::string out = s;
  std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return out;
}

octave_value get_struct_field(const octave_value& s, const std::string& field_name) {
  if (!s.isstruct()) {
    return octave_value();
  }
  try {
    octave_map m = s.map_value();
    Cell c = m.contents(field_name);
    if (c.numel() > 0) {
      return c(0);
    }
  } catch (...) {
  }
  return octave_value();
}

double get_struct_scalar(const octave_value& s, const std::string& field_name, double default_val) {
  octave_value v = get_struct_field(s, field_name);
  if (v.isempty()) {
    return default_val;
  }
  if (v.isnumeric() && v.numel() == 1) {
    return v.double_value();
  }
  if (v.islogical() && v.numel() == 1) {
    return v.bool_value() ? 1.0 : 0.0;
  }
  return default_val;
}

Complex dot_conj(const ComplexColumnVector& a, const ComplexColumnVector& b) {
  const octave_idx_type n = a.numel();
  Complex out = Complex(0.0, 0.0);
  for (octave_idx_type i = 0; i < n; ++i) {
    out += std::conj(a(i)) * b(i);
  }
  return out;
}

double vec_norm2(const ComplexColumnVector& v) {
  const octave_idx_type n = v.numel();
  double acc = 0.0;
  for (octave_idx_type i = 0; i < n; ++i) {
    acc += std::norm(v(i));
  }
  return std::sqrt(acc);
}

ComplexColumnVector matvec_dense(const ComplexMatrix& A, const ComplexColumnVector& x) {
  const octave_idx_type n = A.rows();
  const octave_idx_type m = A.cols();
  ComplexColumnVector y(n);

#ifdef _OPENMP
#pragma omp parallel for schedule(static)
#endif
  for (octave_idx_type i = 0; i < n; ++i) {
    Complex acc = Complex(0.0, 0.0);
    for (octave_idx_type j = 0; j < m; ++j) {
      acc += A(i, j) * x(j);
    }
    y(i) = acc;
  }
  return y;
}

struct DiagPreconditioner {
  bool has_m1 = false;
  bool has_m2 = false;
  ComplexColumnVector inv_m1;
  ComplexColumnVector inv_m2;
};

bool extract_inverse_diagonal(const octave_value& M_val, octave_idx_type n, ComplexColumnVector& inv_diag) {
  if (M_val.isempty() || !M_val.isnumeric()) {
    return false;
  }

  ComplexMatrix M;
  try {
    M = M_val.complex_matrix_value();
  } catch (...) {
    return false;
  }
  if (M.rows() != n || M.cols() != n) {
    return false;
  }

  double offdiag_max = 0.0;
  double diag_max = 0.0;
  for (octave_idx_type i = 0; i < n; ++i) {
    for (octave_idx_type j = 0; j < n; ++j) {
      double aij = std::abs(M(i, j));
      if (i == j) {
        diag_max = std::max(diag_max, aij);
      } else {
        offdiag_max = std::max(offdiag_max, aij);
      }
    }
  }

  const double diag_guard = std::max(1e-12, diag_max * 1e-9);
  if (offdiag_max > diag_guard) {
    return false;
  }

  inv_diag.resize(n);
  for (octave_idx_type i = 0; i < n; ++i) {
    Complex d = M(i, i);
    if (std::abs(d) < 1e-14) {
      return false;
    }
    inv_diag(i) = Complex(1.0, 0.0) / d;
  }
  return true;
}

ComplexColumnVector apply_preconditioner_diag(const ComplexColumnVector& v, const DiagPreconditioner& P) {
  ComplexColumnVector y(v);
  const octave_idx_type n = y.numel();
  if (P.has_m1) {
    for (octave_idx_type i = 0; i < n; ++i) {
      y(i) *= P.inv_m1(i);
    }
  }
  if (P.has_m2) {
    for (octave_idx_type i = 0; i < n; ++i) {
      y(i) *= P.inv_m2(i);
    }
  }
  return y;
}

struct IterResult {
  ComplexColumnVector x;
  int flag = 1;
  double relres = std::numeric_limits<double>::quiet_NaN();
  int iter_count = 0;
  std::string stop_reason = "iter_external_not_run";
};

IterResult solve_bicgstab_dense(const ComplexMatrix& A,
                                const ComplexColumnVector& b,
                                const ComplexColumnVector& x0,
                                const DiagPreconditioner& P,
                                double tol,
                                int maxit) {
  IterResult out;
  const octave_idx_type n = b.numel();
  out.x = x0;
  out.flag = 1;
  out.iter_count = 0;
  out.stop_reason = "iter_external_bicgstab_maxit";

  const double normb = std::max(vec_norm2(b), 1e-30);
  ComplexColumnVector Ax0 = matvec_dense(A, out.x);
  ComplexColumnVector r(n);
  for (octave_idx_type i = 0; i < n; ++i) {
    r(i) = b(i) - Ax0(i);
  }

  double rel = vec_norm2(r) / normb;
  if (rel <= tol) {
    out.flag = 0;
    out.relres = rel;
    out.stop_reason = "iter_external_bicgstab_converged";
    return out;
  }

  ComplexColumnVector r_hat(r);
  ComplexColumnVector p(n);
  ComplexColumnVector v(n);
  ComplexColumnVector s(n);
  ComplexColumnVector t(n);
  ComplexColumnVector p_hat(n);
  ComplexColumnVector s_hat(n);

  for (octave_idx_type i = 0; i < n; ++i) {
    p(i) = Complex(0.0, 0.0);
    v(i) = Complex(0.0, 0.0);
  }

  Complex rho_prev = Complex(1.0, 0.0);
  Complex alpha = Complex(1.0, 0.0);
  Complex omega = Complex(1.0, 0.0);

  for (int k = 1; k <= maxit; ++k) {
    Complex rho = dot_conj(r_hat, r);
    if (std::abs(rho) < 1e-30) {
      out.flag = 2;
      out.iter_count = k - 1;
      out.relres = rel;
      out.stop_reason = "iter_external_breakdown_rho";
      return out;
    }

    const Complex beta = (rho / rho_prev) * (alpha / omega);
    for (octave_idx_type i = 0; i < n; ++i) {
      p(i) = r(i) + beta * (p(i) - omega * v(i));
    }

    p_hat = apply_preconditioner_diag(p, P);
    v = matvec_dense(A, p_hat);
    Complex den = dot_conj(r_hat, v);
    if (std::abs(den) < 1e-30) {
      out.flag = 3;
      out.iter_count = k - 1;
      out.relres = rel;
      out.stop_reason = "iter_external_breakdown_alpha";
      return out;
    }
    alpha = rho / den;

    for (octave_idx_type i = 0; i < n; ++i) {
      s(i) = r(i) - alpha * v(i);
    }

    const double rel_s = vec_norm2(s) / normb;
    if (rel_s <= tol) {
      for (octave_idx_type i = 0; i < n; ++i) {
        out.x(i) += alpha * p_hat(i);
      }
      out.flag = 0;
      out.iter_count = k;
      out.relres = rel_s;
      out.stop_reason = "iter_external_bicgstab_converged";
      return out;
    }

    s_hat = apply_preconditioner_diag(s, P);
    t = matvec_dense(A, s_hat);
    Complex tt = dot_conj(t, t);
    if (std::abs(tt) < 1e-30) {
      out.flag = 4;
      out.iter_count = k;
      out.relres = rel_s;
      out.stop_reason = "iter_external_breakdown_omega";
      return out;
    }
    omega = dot_conj(t, s) / tt;

    for (octave_idx_type i = 0; i < n; ++i) {
      out.x(i) += alpha * p_hat(i) + omega * s_hat(i);
      r(i) = s(i) - omega * t(i);
    }

    rel = vec_norm2(r) / normb;
    out.iter_count = k;
    if (!std::isfinite(rel)) {
      out.flag = 9;
      out.relres = rel;
      out.stop_reason = "iter_external_nonfinite_relres";
      return out;
    }
    if (rel <= tol) {
      out.flag = 0;
      out.relres = rel;
      out.stop_reason = "iter_external_bicgstab_converged";
      return out;
    }
    if (std::abs(omega) < 1e-30) {
      out.flag = 5;
      out.relres = rel;
      out.stop_reason = "iter_external_breakdown_omega_zero";
      return out;
    }

    rho_prev = rho;
  }

  out.flag = 1;
  out.relres = rel;
  out.stop_reason = "iter_external_bicgstab_maxit";
  return out;
}

}  // namespace

DEFUN_DLD(peec_external_krylov_solve_impl, args, nargout,
          "Native external Krylov backend (dense matrix path, Octave .oct).") {
  octave_value_list out;
  (void)nargout;

  if (args.length() < 6) {
    print_usage();
    return out;
  }

  octave_value A_in = args(0);
  octave_value b_in = args(1);
  std::string solver_kind = "bicgstab";
  if (args(2).is_string()) {
    solver_kind = to_lower_copy(args(2).string_value());
  }
  if (solver_kind != "bicgstab" && solver_kind != "gmres") {
    solver_kind = "bicgstab";
  }

  octave_value opts_in = args(3);
  octave_value precond_in = args(4);
  octave_value x0_in = args(5);

  const double tol = std::max(1e-12, get_struct_scalar(opts_in, "tol", 1e-6));
  const int maxit = std::max(1, static_cast<int>(std::round(get_struct_scalar(opts_in, "maxit", 120.0))));

  ComplexColumnVector b;
  try {
    b = b_in.complex_column_vector_value();
  } catch (...) {
    octave_scalar_map info;
    info.assign("flag", 90.0);
    info.assign("relres", octave_NaN);
    info.assign("iter_count", 0.0);
    info.assign("stop_reason", "iter_external_invalid_rhs");
    out(0) = Matrix();
    out(1) = info;
    return out;
  }
  const octave_idx_type n = b.numel();

  ComplexColumnVector x0(n);
  for (octave_idx_type i = 0; i < n; ++i) {
    x0(i) = Complex(0.0, 0.0);
  }
  if (x0_in.isnumeric() && x0_in.numel() == n) {
    try {
      x0 = x0_in.complex_column_vector_value();
    } catch (...) {
      // Keep zero initial guess on conversion failure.
    }
  }

  if (A_in.is_function_handle()) {
    octave_scalar_map info;
    info.assign("flag", 97.0);
    info.assign("relres", octave_NaN);
    info.assign("iter_count", 0.0);
    info.assign("stop_reason", "iter_external_matrix_free_not_supported");
    out(0) = x0;
    out(1) = info;
    return out;
  }

  if (!A_in.isnumeric()) {
    octave_scalar_map info;
    info.assign("flag", 96.0);
    info.assign("relres", octave_NaN);
    info.assign("iter_count", 0.0);
    info.assign("stop_reason", "iter_external_invalid_matrix");
    out(0) = x0;
    out(1) = info;
    return out;
  }

  ComplexMatrix A;
  try {
    A = A_in.complex_matrix_value();
  } catch (...) {
    octave_scalar_map info;
    info.assign("flag", 95.0);
    info.assign("relres", octave_NaN);
    info.assign("iter_count", 0.0);
    info.assign("stop_reason", "iter_external_matrix_conversion_error");
    out(0) = x0;
    out(1) = info;
    return out;
  }
  if (A.rows() != n || A.cols() != n) {
    octave_scalar_map info;
    info.assign("flag", 94.0);
    info.assign("relres", octave_NaN);
    info.assign("iter_count", 0.0);
    info.assign("stop_reason", "iter_external_matrix_size_mismatch");
    out(0) = x0;
    out(1) = info;
    return out;
  }

  DiagPreconditioner P;
  if (precond_in.isstruct()) {
    octave_value M1 = get_struct_field(precond_in, "M1");
    octave_value M2 = get_struct_field(precond_in, "M2");
    P.has_m1 = extract_inverse_diagonal(M1, n, P.inv_m1);
    P.has_m2 = extract_inverse_diagonal(M2, n, P.inv_m2);
  }

  IterResult it = solve_bicgstab_dense(A, b, x0, P, tol, maxit);
  if (solver_kind == "gmres" && it.flag == 0) {
    it.stop_reason = "iter_external_gmres_compat_bicgstab";
  }

  octave_scalar_map info;
  info.assign("flag", static_cast<double>(it.flag));
  info.assign("relres", it.relres);
  info.assign("iter_count", static_cast<double>(it.iter_count));
  info.assign("stop_reason", it.stop_reason);
  info.assign("preconditioner_kind", (P.has_m1 || P.has_m2) ? "diag_only" : "none");

  out(0) = it.x;
  out(1) = info;
  return out;
}
