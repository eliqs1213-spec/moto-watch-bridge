import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let goal: TimeInterval = 12 * 3600
let stage = FeliFastingAnimationPolicy.stage
check(stage(nil, targetSeconds: goal) == .ready, "No ayuno: listo")
check(stage(0, targetSeconds: goal) == .mate, "Inicio: mate")
check(stage(599, targetSeconds: goal) == .mate, "Mate durante los primeros 10 minutos")
check(stage(600, targetSeconds: goal) == .resting, "Después del mate: reposo")
check(stage(goal * 0.4, targetSeconds: goal) == .imaginingFood, "Fase intermedia")
check(stage(goal * 0.7, targetSeconds: goal) == .asado, "Debe mostrar vacío a la parrilla")
check(stage(goal * 0.9, targetSeconds: goal) == .countdown, "Último tramo: reloj")
check(stage(goal, targetSeconds: goal) == .goalReached, "Objetivo de tiempo, sesión sigue activa")
check(stage(nil, targetSeconds: goal, recentlyCompleted: true) == .completed, "Corte real registrado")
check(stage(nil, targetSeconds: goal, recentlyCompleted: false) == .ready, "Corte viejo no activa festejo")
check(stage(-5, targetSeconds: goal) == .mate, "Tiempo negativo se trata como recién iniciado")
print("Feli Ayuno animation stage checks passed")
