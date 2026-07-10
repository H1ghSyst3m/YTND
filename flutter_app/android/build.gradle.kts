// Repository declarations moved to dependencyResolutionManagement in settings.gradle.kts
// per Flutter/AGP 8+ recommendations.

val flutterBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(flutterBuildDir)

subprojects {
    val subprojectBuildDir = flutterBuildDir.dir(project.name)
    project.layout.buildDirectory.value(subprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
